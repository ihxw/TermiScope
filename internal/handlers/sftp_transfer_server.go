package handlers

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/models"
)

// serverSSHBundle is a temp SSH config + credentials for scp -3 on the TermiScope host.
type serverSSHBundle struct {
	dir        string
	configPath string
}

func (b *serverSSHBundle) cleanup() {
	if b != nil && b.dir != "" {
		os.RemoveAll(b.dir)
	}
}

func writeServerSSHBundle(srcHost, dstHost models.SSHHost, srcPass, srcKey, dstPass, dstKey string) (*serverSSHBundle, error) {
	dir, err := os.MkdirTemp("", "ts-server-scp-")
	if err != nil {
		return nil, err
	}
	bundle := &serverSSHBundle{dir: dir, configPath: filepath.Join(dir, "config")}

	knownHosts := filepath.Join(dir, "known_hosts")
	if err := os.WriteFile(knownHosts, nil, 0600); err != nil {
		bundle.cleanup()
		return nil, err
	}

	var cfg strings.Builder
	cfg.WriteString("Host ts-src ts-dst\n  StrictHostKeyChecking accept-new\n  UserKnownHostsFile ")
	cfg.WriteString(knownHosts)
	cfg.WriteString("\n\n")

	if err := appendServerSSHHost(&cfg, "ts-src", srcHost, srcPass, srcKey, dir); err != nil {
		bundle.cleanup()
		return nil, err
	}
	cfg.WriteString("\n")
	if err := appendServerSSHHost(&cfg, "ts-dst", dstHost, dstPass, dstKey, dir); err != nil {
		bundle.cleanup()
		return nil, err
	}

	if err := os.WriteFile(bundle.configPath, []byte(cfg.String()), 0600); err != nil {
		bundle.cleanup()
		return nil, err
	}
	return bundle, nil
}

func appendServerSSHHost(cfg *strings.Builder, alias string, host models.SSHHost, password, privateKey, dir string) error {
	if err := validateSSHConnectionFields(host.Host, host.Username); err != nil {
		return fmt.Errorf("invalid SSH host configuration: %w", err)
	}

	port := host.Port
	if port == 0 {
		port = 22
	}
	fmt.Fprintf(cfg, "Host %s\n  HostName %s\n  Port %d\n  User %s\n", alias, sshConfigValue(host.Host), port, sshConfigValue(host.Username))

	if privateKey != "" {
		keyPath := filepath.Join(dir, alias+".key")
		normalized := strings.ReplaceAll(privateKey, "\r\n", "\n")
		normalized = strings.ReplaceAll(normalized, "\r", "\n")
		if err := os.WriteFile(keyPath, []byte(strings.TrimSpace(normalized)+"\n"), 0600); err != nil {
			return err
		}
		fmt.Fprintf(cfg, "  IdentityFile %s\n  IdentitiesOnly yes\n", keyPath)
		return nil
	}
	if password == "" {
		return fmt.Errorf("host %s has no SSH key or password", host.Name)
	}
	if _, err := exec.LookPath("sshpass"); err != nil {
		return fmt.Errorf("sshpass not installed on TermiScope server (required for password auth on %s)", host.Name)
	}
	passPath := filepath.Join(dir, alias+".pass")
	if err := os.WriteFile(passPath, []byte(password), 0600); err != nil {
		return err
	}
	knownHosts := filepath.Join(dir, "known_hosts")
	fmt.Fprintf(cfg,
		"  ProxyCommand sshpass -f %s ssh -F /dev/null -o UserKnownHostsFile=%s -o StrictHostKeyChecking=accept-new -p %%p -l %%r -W %%h:%%p %%h\n",
		passPath, knownHosts,
	)
	return nil
}

func sshConfigValue(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `"`, `\"`)
	return `"` + value + `"`
}

func serverSCPEndpoints(resolvedSrc, resolvedDest, destFileName string, isDir, destIsDir bool) (src, dst string) {
	src = "ts-src:" + resolvedSrc
	dst = "ts-dst:" + scpDestPath(resolvedDest, destFileName, isDir, destIsDir)
	return src, dst
}

func (h *SftpHandler) pollServerTransferProgress(
	ctx context.Context,
	c *gin.Context,
	userID uint,
	dstHostID, destPath string,
	totalSize int64,
) {
	if totalSize <= 0 {
		return
	}
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	var lastPct int
	start := time.Now()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			written := h.remotePathWrittenBytes(userID, dstHostID, destPath)
			if written <= 0 {
				continue
			}
			pct := int(written * 100 / totalSize)
			if pct > 100 {
				pct = 100
			}
			if pct == lastPct {
				continue
			}
			lastPct = pct
			elapsed := time.Since(start).Seconds()
			if elapsed < 0.1 {
				elapsed = 0.1
			}
			speedStr := formatSpeed(float64(written) / elapsed)
			sendTransferEvent(c, map[string]interface{}{
				"type":        "progress",
				"percent":     pct,
				"speed":       speedStr,
				"transferred": written,
				"total":       totalSize,
			})
		}
	}
}

func (h *SftpHandler) remotePathWrittenBytes(userID uint, hostID, remotePath string) int64 {
	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		return 0
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	stat, err := sftpClient.Stat(remotePath)
	if err != nil {
		return 0
	}
	if !stat.IsDir() {
		return stat.Size()
	}

	var total int64
	walker := sftpClient.Walk(remotePath)
	for walker.Step() {
		if walker.Err() != nil || walker.Stat().IsDir() {
			continue
		}
		total += walker.Stat().Size()
	}
	return total
}

// tryServerSCP3 runs OpenSSH scp -3 on the TermiScope host (optimized relay, faster than SFTP loop).
// Returns (attempted, success).
func (h *SftpHandler) tryServerSCP3(
	c *gin.Context,
	userID uint,
	srcHost, dstHost models.SSHHost,
	srcPass, srcKey, dstPass, dstKey string,
	resolvedSrc, resolvedDest, destFileName string,
	isDir bool,
	destIsDir bool,
	totalSize int64,
) (attempted bool, success bool) {
	if _, err := exec.LookPath("scp"); err != nil {
		return false, false
	}

	bundle, err := writeServerSSHBundle(srcHost, dstHost, srcPass, srcKey, dstPass, dstKey)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{
			"type":    "info",
			"message": "server scp unavailable: " + err.Error(),
		})
		return false, false
	}
	defer bundle.cleanup()

	srcArg, dstArg := serverSCPEndpoints(resolvedSrc, resolvedDest, destFileName, isDir, destIsDir)
	args := []string{
		"-3",
		"-F", bundle.configPath,
		"-o", "BatchMode=yes",
		"-o", "ConnectTimeout=30",
	}
	if isDir {
		args = append(args, "-r")
	}
	args = append(args, srcArg, dstArg)

	sendTransferEvent(c, map[string]interface{}{
		"type":    "info",
		"message": "using server scp (data routed through TermiScope host)",
	})

	ctx, cancel := context.WithCancel(c.Request.Context())
	defer cancel()

	destMonitorPath := resolvedDest
	if destIsDir || destFileName != "" {
		destMonitorPath = joinRemotePath(resolvedDest, destMonitorBaseName(resolvedSrc, destFileName))
	}
	go h.pollServerTransferProgress(ctx, c, userID, fmt.Sprintf("%d", dstHost.ID), destMonitorPath, totalSize)

	cmd := exec.CommandContext(c.Request.Context(), "scp", args...)
	output, err := cmd.CombinedOutput()
	cancel()
	if err != nil {
		msg := strings.TrimSpace(string(output))
		if msg == "" {
			msg = err.Error()
		}
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "server scp failed, falling back: " + msg})
		return true, false
	}

	sendTransferEvent(c, map[string]interface{}{"type": "complete", "method": "server-scp"})
	return true, true
}

func destMonitorBaseName(resolvedSrc, destFileName string) string {
	if destFileName != "" {
		return path.Base(destFileName)
	}
	return path.Base(resolvedSrc)
}
