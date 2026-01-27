package updater

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/ihxw/termiscope/internal/utils"
)

type Release struct {
	TagName string  `json:"tag_name"`
	Name    string  `json:"name"`
	Body    string  `json:"body"`
	Assets  []Asset `json:"assets"`
}

type Asset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int64  `json:"size"`
}

type UpdateInfo struct {
	Version     string `json:"version"`
	DownloadURL string `json:"download_url"`
	Body        string `json:"body"`
	Size        int64  `json:"size"`
}

// CheckForUpdate checks if a newer version is available on GitHub
func CheckForUpdate(currentVersion string) (*UpdateInfo, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get("https://api.github.com/repos/ihxw/TermiScope/releases/latest")
	if err != nil {
		return nil, fmt.Errorf("failed to check for updates: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub API error: %s", resp.Status)
	}

	var release Release
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("failed to decode release info: %v", err)
	}

	latestVersion := strings.TrimPrefix(release.TagName, "v")
	currentVersion = strings.TrimPrefix(currentVersion, "v")

	if latestVersion == currentVersion {
		return nil, nil
	}

	// Simple version comparison: if not equal, assume update (unless dev/test/etc)
	// Ideally use semver lib, but string compare for equality is good first step.
	// If current is "dev", maybe ignore unless forced?
	// User request implies manual check/update flow, so returning info is fine.

	osName := runtime.GOOS
	arch := runtime.GOARCH

	// Adjust for typical naming conventions
	// TermiScope-Windows-x86_64.zip
	// TermiScope-Linux-x86_64.tar.gz
	// TermiScope-Darwin-x86_64.tar.gz

	candidates := []Asset{}
	for _, asset := range release.Assets {
		name := strings.ToLower(asset.Name)
		if strings.Contains(name, strings.ToLower(osName)) {
			if arch == "amd64" && (strings.Contains(name, "x86_64") || strings.Contains(name, "amd64")) {
				candidates = append(candidates, asset)
			} else if arch == "arm64" && (strings.Contains(name, "arm64") || strings.Contains(name, "aarch64")) {
				candidates = append(candidates, asset)
			}
		}
	}

	// If multiple candidates (e.g. .zip and .tar.gz), prefer zip on windows, tar.gz on others
	var bestAsset *Asset
	for _, asset := range candidates {
		name := strings.ToLower(asset.Name)
		if runtime.GOOS == "windows" {
			if strings.HasSuffix(name, ".zip") {
				bestAsset = &asset
				break
			} else if strings.HasSuffix(name, ".exe") {
				bestAsset = &asset
			}
		} else {
			if strings.HasSuffix(name, ".tar.gz") {
				bestAsset = &asset
				break
			}
		}
	}

	// Fallback to first candidate if no preference match
	if bestAsset == nil && len(candidates) > 0 {
		bestAsset = &candidates[0]
	}

	if bestAsset == nil {
		return nil, fmt.Errorf("no compatible asset found for %s/%s", osName, arch)
	}

	return &UpdateInfo{
		Version:     latestVersion,
		DownloadURL: bestAsset.BrowserDownloadURL,
		Body:        release.Body,
		Size:        bestAsset.Size,
	}, nil
}

// PerformUpdate downloads, extracts (if needed), replaces, and restarts
func PerformUpdate(downloadURL string) error {
	// 1. Download
	resp, err := http.Get(downloadURL)
	if err != nil {
		return fmt.Errorf("download failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download failed with status: %s", resp.Status)
	}

	// 2. Save to Temp
	tmpFile, err := os.CreateTemp("", "termiscope_update_RAW_*")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name()) // Clean up raw download

	_, err = io.Copy(tmpFile, resp.Body)
	tmpFile.Close()
	if err != nil {
		return fmt.Errorf("failed to save download: %v", err)
	}

	// 3. Extract if needed
	var binaryPath string

	lowerURL := strings.ToLower(downloadURL)
	if strings.HasSuffix(lowerURL, ".zip") {
		// Extract ZIP
		extractedPath, err := extractZip(tmpFile.Name())
		if err != nil {
			return fmt.Errorf("failed to unzip: %v", err)
		}
		defer os.Remove(extractedPath) // Clean up extracted binary after install
		binaryPath = extractedPath
	} else if strings.HasSuffix(lowerURL, ".tar.gz") {
		// Extract TarGz
		extractedPath, err := extractTarGz(tmpFile.Name())
		if err != nil {
			return fmt.Errorf("failed to untar: %v", err)
		}
		defer os.Remove(extractedPath)
		binaryPath = extractedPath
	} else {
		// Assume raw binary
		binaryPath = tmpFile.Name()
	}

	// 4. Locate current executable
	exePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to find executable: %v", err)
	}
	exePath, err = filepath.Abs(exePath)
	if err != nil {
		return err
	}

	// 5. Backup current
	oldPath := exePath + ".old"
	os.Remove(oldPath) // Remove existing backup
	if err := os.Rename(exePath, oldPath); err != nil {
		return fmt.Errorf("failed to backup current binary: %v", err)
	}

	// 6. Install new binary
	if err := copyFile(binaryPath, exePath); err != nil {
		// Rollback
		os.Rename(oldPath, exePath)
		return fmt.Errorf("failed to install new binary: %v", err)
	}

	// 7. Chmod +x
	if runtime.GOOS != "windows" {
		os.Chmod(exePath, 0755)
	}

	// 8. Restart
	return utils.RestartSelf()
}

// Helpers

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	if err != nil {
		return err
	}
	return out.Sync()
}

func extractZip(zipPath string) (string, error) {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return "", err
	}
	defer r.Close()

	// Find the largest file, assume it's the binary (simple heuristic)
	// Or looks for file with name containing 'termiscope'
	var candidate *zip.File
	var maxSize int64

	for _, f := range r.File {
		if f.FileInfo().IsDir() {
			continue
		}
		// Skip dotfiles, readme, license
		name := strings.ToLower(f.Name)
		if strings.HasSuffix(name, ".md") || strings.HasSuffix(name, ".txt") {
			continue
		}
		if f.FileInfo().Size() > maxSize {
			maxSize = f.FileInfo().Size()
			candidate = f
		}
	}

	if candidate == nil {
		return "", fmt.Errorf("no binary found in zip")
	}

	// Extract candidate
	rc, err := candidate.Open()
	if err != nil {
		return "", err
	}
	defer rc.Close()

	tmpBin, err := os.CreateTemp("", "termiscope_new_bin_*")
	if err != nil {
		return "", err
	}
	defer tmpBin.Close()

	_, err = io.Copy(tmpBin, rc)
	if err != nil {
		return "", err
	}

	return tmpBin.Name(), nil
}

func extractTarGz(tarPath string) (string, error) {
	f, err := os.Open(tarPath)
	if err != nil {
		return "", err
	}
	defer f.Close()

	gzr, err := gzip.NewReader(f)
	if err != nil {
		return "", err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)

	// Similar heuristic: find largest file? Or first executable?
	// Tars are stream, so we must iterate.
	// We'll extract to a temp file directly if matches logic.

	// Create a temp file to store potential candidate
	tmpBin, err := os.CreateTemp("", "termiscope_new_bin_*")
	if err != nil {
		return "", err
	}

	// We might overwrite if we find a better candidate? No, tar stream.
	// Let's assume the server binary is the largest file or named 'termiscope-server'
	// Since we receive the stream, calculating size beforehand is hard.
	// But `Header` has size.

	// This is tricky with single pass.
	// Let's write the valid-looking file to tmp.
	// If we encounter a better one?
	// Let's assume the release archive is clean and contains the binary.
	// Usually: `termiscope-server`

	found := false

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", err
		}

		if header.Typeflag == tar.TypeReg {
			name := filepath.Base(header.Name)
			// Heuristic: Name contains 'termiscope' and not an extension like .md/.txt
			if strings.Contains(strings.ToLower(name), "termiscope") && !strings.Contains(name, ".") {
				// Likely the binary (linux/mac has no extension)
				if _, err := io.Copy(tmpBin, tr); err != nil {
					tmpBin.Close()
					return "", err
				}
				found = true
				break
			} else if strings.HasSuffix(strings.ToLower(name), ".exe") {
				// Windows in tar.gz? rare but possible
				if _, err := io.Copy(tmpBin, tr); err != nil {
					tmpBin.Close()
					return "", err
				}
				found = true
				break
			}
		}
	}

	tmpBin.Close() // Close to flush

	if !found {
		// If strict name match failed, maybe look for any large file executable logic?
		// For now fail.
		os.Remove(tmpBin.Name())
		return "", fmt.Errorf("binary not found in tar.gz")
	}

	return tmpBin.Name(), nil
}
