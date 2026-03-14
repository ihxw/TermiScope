package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/kardianos/service"
)

const (
	agentUpdateCheckInterval = 15 * time.Minute
	agentUpdateRetryDelay   = 10 * time.Minute
	agentServiceName        = "TermiScopeAgent"
)

type agentUpdateManifest struct {
	Version   string `json:"version"`
	Filename  string `json:"filename"`
	SHA256    string `json:"sha256"`
	Size      int64  `json:"size"`
	Signature string `json:"signature"`
}

func attemptAgentSelfUpdate(client *http.Client) error {
	manifest, err := fetchAgentUpdateManifest(client)
	if err != nil {
		return err
	}
	if manifest == nil {
		return nil
	}

	logError("Agent update detected: current=%s latest=%s", Version, manifest.Version)
	return downloadAndApplyAgentUpdate(client, manifest)
}

func fetchAgentUpdateManifest(client *http.Client) (*agentUpdateManifest, error) {
	filename, err := currentAgentFilename()
	if err != nil {
		return nil, err
	}

	manifestURL := fmt.Sprintf(
		"%s/api/monitor/agent-manifest?host_id=%d&os=%s&arch=%s",
		strings.TrimRight(serverURL, "/"),
		hostID,
		runtime.GOOS,
		runtime.GOARCH,
	)

	req, err := http.NewRequest(http.MethodGet, manifestURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("manifest request failed: %s %s", resp.Status, strings.TrimSpace(string(body)))
	}

	var manifest agentUpdateManifest
	if err := json.NewDecoder(resp.Body).Decode(&manifest); err != nil {
		return nil, fmt.Errorf("failed to decode manifest: %w", err)
	}

	if manifest.Filename != filename {
		return nil, fmt.Errorf("manifest filename mismatch: expected %s got %s", filename, manifest.Filename)
	}
	if manifest.Version == "" || manifest.SHA256 == "" || manifest.Signature == "" || manifest.Size <= 0 {
		return nil, fmt.Errorf("manifest is incomplete")
	}
	if !verifyAgentManifestSignature(secret, &manifest) {
		return nil, fmt.Errorf("manifest signature verification failed")
	}
	if cleanVersionString(manifest.Version) == cleanVersionString(Version) {
		return nil, nil
	}

	return &manifest, nil
}

func downloadAndApplyAgentUpdate(client *http.Client, manifest *agentUpdateManifest) error {
	exePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to resolve executable path: %w", err)
	}
	exePath, err = filepath.Abs(exePath)
	if err != nil {
		return err
	}
	exeDir := filepath.Dir(exePath)

	tmpFile, err := os.CreateTemp(exeDir, "termiscope-agent-update-*")
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	downloadURL := fmt.Sprintf(
		"%s/api/monitor/agent/%s?host_id=%d",
		strings.TrimRight(serverURL, "/"),
		manifest.Filename,
		hostID,
	)

	req, err := http.NewRequest(http.MethodGet, downloadURL, nil)
	if err != nil {
		tmpFile.Close()
		return err
	}
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := client.Do(req)
	if err != nil {
		tmpFile.Close()
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		tmpFile.Close()
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("download failed: %s %s", resp.Status, strings.TrimSpace(string(body)))
	}

	hasher := sha256.New()
	written, err := io.Copy(io.MultiWriter(tmpFile, hasher), resp.Body)
	closeErr := tmpFile.Close()
	if err != nil {
		return fmt.Errorf("failed to save update: %w", err)
	}
	if closeErr != nil {
		return fmt.Errorf("failed to finalize update file: %w", closeErr)
	}
	if written != manifest.Size {
		return fmt.Errorf("download size mismatch: expected %d got %d", manifest.Size, written)
	}
	if actualHash := hex.EncodeToString(hasher.Sum(nil)); !strings.EqualFold(actualHash, manifest.SHA256) {
		return fmt.Errorf("download checksum mismatch")
	}

	if runtime.GOOS != "windows" {
		if err := os.Chmod(tmpPath, 0755); err != nil {
			return fmt.Errorf("failed to chmod update binary: %w", err)
		}
	}

	if runtime.GOOS == "windows" {
		return stageWindowsAgentUpdate(tmpPath, exePath)
	}

	if err := installUnixAgentBinary(tmpPath, exePath); err != nil {
		return err
	}

	return restartUpdatedAgent(exePath)
}

func installUnixAgentBinary(tmpPath, exePath string) error {
	newPath := exePath + ".new"
	oldPath := exePath + ".old"
	os.Remove(newPath)
	os.Remove(oldPath)

	if err := os.Rename(tmpPath, newPath); err != nil {
		return fmt.Errorf("failed to stage new binary: %w", err)
	}
	if err := os.Rename(exePath, oldPath); err != nil {
		os.Rename(newPath, tmpPath)
		return fmt.Errorf("failed to backup current agent: %w", err)
	}
	if err := os.Rename(newPath, exePath); err != nil {
		os.Rename(oldPath, exePath)
		os.Rename(newPath, tmpPath)
		return fmt.Errorf("failed to activate new agent: %w", err)
	}

	return nil
}

func stageWindowsAgentUpdate(tmpPath, exePath string) error {
	scriptPath := filepath.Join(filepath.Dir(exePath), "restart_termiscope_agent.bat")
	content := fmt.Sprintf("@echo off\r\n"+
		"timeout /t 2 >nul\r\n"+
		"copy /Y \"%s\" \"%s\" >nul\r\n"+
		"\"%s\" -service start >nul 2>&1\r\n"+
		"if errorlevel 1 start \"\" \"%s\" %s\r\n"+
		"del \"%s\"\r\n"+
		"del \"%%~f0\"\r\n",
		tmpPath,
		exePath,
		exePath,
		exePath,
		windowsCommandLineArgs(),
		tmpPath,
	)

	if err := os.WriteFile(scriptPath, []byte(content), 0755); err != nil {
		return fmt.Errorf("failed to write restart script: %w", err)
	}

	cmd := exec.Command("cmd", "/C", "start", "", scriptPath)
	cmd.Dir = filepath.Dir(exePath)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to launch restart script: %w", err)
	}

	os.Exit(0)
	return nil
}

func restartUpdatedAgent(exePath string) error {
	if !service.Interactive() {
		// If running as a service on Linux, try to restart via systemctl
		if runtime.GOOS == "linux" {
			cmd := exec.Command("systemctl", "restart", "--no-block", agentServiceName+".service")
			if err := cmd.Start(); err != nil {
				logError("Failed to trigger systemd restart: %v", err)
			} else {
				logError("Triggered systemd restart for %s.service", agentServiceName)
			}
		}
		os.Exit(0)
		return nil
	}

	scriptPath := filepath.Join(filepath.Dir(exePath), "restart_termiscope_agent.sh")
	content := fmt.Sprintf("#!/bin/sh\n"+
		"sleep 2\n"+
		"cd \"%s\" || exit 1\n"+
		"\"%s\" %s > /dev/null 2>&1 &\n"+
		"rm -f \"$0\"\n",
		filepath.Dir(exePath),
		exePath,
		shellCommandLineArgs(),
	)

	if err := os.WriteFile(scriptPath, []byte(content), 0755); err != nil {
		return fmt.Errorf("failed to write restart script: %w", err)
	}

	cmd := exec.Command("/bin/sh", scriptPath)
	cmd.Dir = filepath.Dir(exePath)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to launch restart script: %w", err)
	}

	os.Exit(0)
	return nil
}

func currentAgentFilename() (string, error) {
	switch runtime.GOOS {
	case "linux":
		switch runtime.GOARCH {
		case "amd64", "arm64", "arm":
			return fmt.Sprintf("termiscope-agent-linux-%s", runtime.GOARCH), nil
		}
	case "darwin":
		switch runtime.GOARCH {
		case "amd64", "arm64":
			return fmt.Sprintf("termiscope-agent-darwin-%s", runtime.GOARCH), nil
		}
	case "windows":
		if runtime.GOARCH == "amd64" {
			return "termiscope-agent-windows-amd64.exe", nil
		}
	}

	return "", fmt.Errorf("unsupported platform for auto-update: %s/%s", runtime.GOOS, runtime.GOARCH)
}

func verifyAgentManifestSignature(sharedSecret string, manifest *agentUpdateManifest) bool {
	payload := fmt.Sprintf("%s\n%s\n%s\n%d", manifest.Version, manifest.Filename, manifest.SHA256, manifest.Size)
	mac := hmac.New(sha256.New, []byte(sharedSecret))
	mac.Write([]byte(payload))
	expected := mac.Sum(nil)
	actual, err := hex.DecodeString(manifest.Signature)
	if err != nil {
		return false
	}
	return hmac.Equal(actual, expected)
}

func cleanVersionString(version string) string {
	return strings.TrimSpace(strings.TrimPrefix(version, "v"))
}

func shellCommandLineArgs() string {
	args := []string{
		"-server", shellQuote(serverURL),
		"-secret", shellQuote(secret),
		"-id", shellQuote(fmt.Sprintf("%d", hostID)),
	}
	if insecure {
		args = append(args, "-insecure")
	}
	return strings.Join(args, " ")
}

func windowsCommandLineArgs() string {
	args := []string{
		"-server", windowsQuote(serverURL),
		"-secret", windowsQuote(secret),
		"-id", windowsQuote(fmt.Sprintf("%d", hostID)),
	}
	if insecure {
		args = append(args, "-insecure")
	}
	return strings.Join(args, " ")
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func windowsQuote(value string) string {
	escaped := strings.ReplaceAll(value, "\"", "\\\"")
	return "\"" + escaped + "\""
}