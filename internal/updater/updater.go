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
func PerformUpdate(downloadURL string, statusCallback func(string)) error {
	if statusCallback != nil {
		statusCallback("downloading")
	}
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

	if statusCallback != nil {
		statusCallback("extracting")
	}

	// 3. Extract if needed
	var binaryPath string
	var packageRoot string
	var extractedRoot string

	lowerURL := strings.ToLower(downloadURL)
	if strings.HasSuffix(lowerURL, ".zip") {
		extractedRoot, packageRoot, err = extractZip(tmpFile.Name())
		if err != nil {
			return fmt.Errorf("failed to unzip: %v", err)
		}
		defer os.RemoveAll(extractedRoot)
	} else if strings.HasSuffix(lowerURL, ".tar.gz") {
		extractedRoot, packageRoot, err = extractTarGz(tmpFile.Name())
		if err != nil {
			return fmt.Errorf("failed to untar: %v", err)
		}
		defer os.RemoveAll(extractedRoot)
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
	exeDir := filepath.Dir(exePath)

	if packageRoot != "" {
		binaryPath, err = findPackageBinary(packageRoot)
		if err != nil {
			return err
		}
	}

	// 5. Backup current
	oldPath := exePath + ".old"
	os.Remove(oldPath) // Remove existing backup
	if err := os.Rename(exePath, oldPath); err != nil {
		return fmt.Errorf("failed to backup current binary: %v", err)
	}

	if statusCallback != nil {
		statusCallback("installing")
	}

	// 6. Install new binary
	if err := copyFile(binaryPath, exePath); err != nil {
		// Rollback
		os.Rename(oldPath, exePath)
		return fmt.Errorf("failed to install new binary: %v", err)
	}

	if packageRoot != "" {
		if err := syncPackageAssets(packageRoot, exeDir); err != nil {
			os.Rename(oldPath, exePath)
			return fmt.Errorf("failed to sync package assets: %v", err)
		}
	}

	// Remove stale agent hashes cache so it gets regenerated on next startup
	os.Remove(filepath.Join(exeDir, "agent_hashes.json"))

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

func extractZip(zipPath string) (string, string, error) {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return "", "", err
	}
	defer r.Close()

	extractDir, err := os.MkdirTemp("", "termiscope_update_zip_*")
	if err != nil {
		return "", "", err
	}

	for _, f := range r.File {
		targetPath, err := safeExtractPath(extractDir, f.Name)
		if err != nil {
			os.RemoveAll(extractDir)
			return "", "", err
		}

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(targetPath, 0755); err != nil {
				os.RemoveAll(extractDir)
				return "", "", err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
			os.RemoveAll(extractDir)
			return "", "", err
		}

		rc, err := f.Open()
		if err != nil {
			os.RemoveAll(extractDir)
			return "", "", err
		}

		out, err := os.OpenFile(targetPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, f.Mode())
		if err != nil {
			rc.Close()
			os.RemoveAll(extractDir)
			return "", "", err
		}

		if _, err := io.Copy(out, rc); err != nil {
			out.Close()
			rc.Close()
			os.RemoveAll(extractDir)
			return "", "", err
		}

		out.Close()
		rc.Close()
	}

	packageRoot, err := detectPackageRoot(extractDir)
	if err != nil {
		os.RemoveAll(extractDir)
		return "", "", err
	}

	return extractDir, packageRoot, nil
}

func extractTarGz(tarPath string) (string, string, error) {
	f, err := os.Open(tarPath)
	if err != nil {
		return "", "", err
	}
	defer f.Close()

	gzr, err := gzip.NewReader(f)
	if err != nil {
		return "", "", err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)
	extractDir, err := os.MkdirTemp("", "termiscope_update_targz_*")
	if err != nil {
		return "", "", err
	}

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			os.RemoveAll(extractDir)
			return "", "", err
		}

		targetPath, err := safeExtractPath(extractDir, header.Name)
		if err != nil {
			os.RemoveAll(extractDir)
			return "", "", err
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(targetPath, 0755); err != nil {
				os.RemoveAll(extractDir)
				return "", "", err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
				os.RemoveAll(extractDir)
				return "", "", err
			}

			out, err := os.OpenFile(targetPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, os.FileMode(header.Mode))
			if err != nil {
				os.RemoveAll(extractDir)
				return "", "", err
			}

			if _, err := io.Copy(out, tr); err != nil {
				out.Close()
				os.RemoveAll(extractDir)
				return "", "", err
			}
			out.Close()
		}
	}

	packageRoot, err := detectPackageRoot(extractDir)
	if err != nil {
		os.RemoveAll(extractDir)
		return "", "", err
	}

	return extractDir, packageRoot, nil
}

func detectPackageRoot(extractDir string) (string, error) {
	entries, err := os.ReadDir(extractDir)
	if err != nil {
		return "", err
	}

	if len(entries) == 1 && entries[0].IsDir() {
		return filepath.Join(extractDir, entries[0].Name()), nil
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			return extractDir, nil
		}
	}

	if len(entries) > 0 {
		return extractDir, nil
	}

	return "", fmt.Errorf("update package is empty")
}

func findPackageBinary(packageRoot string) (string, error) {
	binaryName := "TermiScope"
	if runtime.GOOS == "windows" {
		binaryName += ".exe"
	}

	binaryPath := filepath.Join(packageRoot, binaryName)
	if _, err := os.Stat(binaryPath); err != nil {
		return "", fmt.Errorf("updated server binary not found in package: %s", binaryName)
	}

	return binaryPath, nil
}

func syncPackageAssets(packageRoot, installDir string) error {
	for _, dirName := range []string{"agents", "scripts", "web"} {
		srcPath := filepath.Join(packageRoot, dirName)
		if _, err := os.Stat(srcPath); err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return err
		}

		dstPath := filepath.Join(installDir, dirName)
		if err := os.RemoveAll(dstPath); err != nil {
			return err
		}
		if err := copyDir(srcPath, dstPath); err != nil {
			return err
		}
	}

	return nil
}

func copyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		relPath, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}

		targetPath := filepath.Join(dst, relPath)
		if info.IsDir() {
			return os.MkdirAll(targetPath, info.Mode())
		}

		if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
			return err
		}

		if err := copyFile(path, targetPath); err != nil {
			return err
		}

		return os.Chmod(targetPath, info.Mode())
	})
}

func safeExtractPath(baseDir, archivePath string) (string, error) {
	cleanPath := filepath.Clean(archivePath)
	targetPath := filepath.Join(baseDir, cleanPath)
	basePrefix := baseDir + string(os.PathSeparator)
	if targetPath != baseDir && !strings.HasPrefix(targetPath, basePrefix) {
		return "", fmt.Errorf("invalid archive path: %s", archivePath)
	}
	return targetPath, nil
}
