package handlers

import (
	"bufio"
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
	"github.com/ihxw/termiscope/internal/ssh"
	"github.com/ihxw/termiscope/internal/utils"
	cryptossh "golang.org/x/crypto/ssh"
)

// serverSSHBundle is a temp SSH config + credentials for scp -3 on the TermiScope host.
type serverSSHBundle struct {
	dir        string
	configPath string
}

var scanSSHHostKeys = func(host string, port int) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "ssh-keyscan", "-T", "10", "-p", fmt.Sprintf("%d", port), "--", host).Output()
}

func verifiedKnownHostLines(host models.SSHHost) ([]byte, error) {
	if strings.TrimSpace(host.Fingerprint) == "" {
		return nil, fmt.Errorf("host %s has no trusted SSH fingerprint", host.Name)
	}
	port := host.Port
	if port == 0 {
		port = 22
	}
	output, err := scanSSHHostKeys(host.Host, port)
	if err != nil {
		return nil, fmt.Errorf("scan SSH host key for %s: %w", host.Name, err)
	}
	var verified strings.Builder
	var observed []string
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		_, _, key, _, _, parseErr := cryptossh.ParseKnownHosts([]byte(line + "\n"))
		if parseErr != nil {
			continue
		}
		fingerprint := cryptossh.FingerprintSHA256(key)
		observed = append(observed, fingerprint)
		if fingerprint == host.Fingerprint {
			verified.WriteString(line)
			verified.WriteByte('\n')
		}
	}
	if verified.Len() == 0 {
		return nil, fmt.Errorf("SSH fingerprint mismatch for %s: expected %s, observed %s", host.Name, host.Fingerprint, strings.Join(observed, ", "))
	}
	return []byte(verified.String()), nil
}

func (b *serverSSHBundle) cleanup() {
	if b != nil && b.dir != "" {
		os.RemoveAll(b.dir)
	}
}

func writeServerSSHBundle(srcHost, dstHost models.SSHHost, srcPass, srcKey, dstPass, dstKey string) (*serverSSHBundle, error) {
	if err := validateSSHConnectionFields(srcHost.Host, srcHost.Username); err != nil {
		return nil, fmt.Errorf("invalid source SSH host configuration: %w", err)
	}
	if err := validateSSHConnectionFields(dstHost.Host, dstHost.Username); err != nil {
		return nil, fmt.Errorf("invalid destination SSH host configuration: %w", err)
	}
	dir, err := os.MkdirTemp("", "ts-server-scp-")
	if err != nil {
		return nil, err
	}
	bundle := &serverSSHBundle{dir: dir, configPath: filepath.Join(dir, "config")}

	knownHosts := filepath.Join(dir, "known_hosts")
	knownHostData := make([]byte, 0, 1024)
	for _, host := range []models.SSHHost{srcHost, dstHost} {
		lines, verifyErr := verifiedKnownHostLines(host)
		if verifyErr != nil {
			bundle.cleanup()
			return nil, verifyErr
		}
		knownHostData = append(knownHostData, lines...)
	}
	if err := os.WriteFile(knownHosts, knownHostData, 0600); err != nil {
		bundle.cleanup()
		return nil, err
	}

	var cfg strings.Builder
	cfg.WriteString("Host ts-src ts-dst\n  StrictHostKeyChecking yes\n  UserKnownHostsFile ")
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
		"  ProxyCommand sshpass -f %s ssh -F /dev/null -o UserKnownHostsFile=%s -o StrictHostKeyChecking=yes -p %%p -l %%r -W %%h:%%p %%h\n",
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
	isDir bool,
) {
	if totalSize <= 0 {
		return
	}
	sftpClient, sshClient, err := h.getSftpClient(userID, dstHostID)
	if err != nil {
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	interval := 750 * time.Millisecond
	if isDir {
		interval = 2 * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	var lastPct int
	start := time.Now()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			var written int64
			if isDir {
				written, _ = remoteDUSize(ctx, sshClient, destPath)
			} else if stat, statErr := sftpClient.Stat(destPath); statErr == nil {
				written = stat.Size()
			}
			if written <= 0 {
				continue
			}
			pct := int(written * 100 / totalSize)
			if pct >= 100 {
				pct = 99
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

func remoteDUSize(ctx context.Context, sshClient *ssh.SSHClient, remotePath string) (int64, bool) {
	session, err := sshClient.GetRawClient().NewSession()
	if err != nil {
		return 0, false
	}
	type outputResult struct {
		data []byte
		err  error
	}
	result := make(chan outputResult, 1)
	go func() {
		data, outputErr := session.Output("du -sk " + utils.ShellEscape(remotePath))
		result <- outputResult{data: data, err: outputErr}
	}()
	var output []byte
	select {
	case <-ctx.Done():
		_ = session.Close()
		return 0, false
	case completed := <-result:
		_ = session.Close()
		if completed.err != nil {
			return 0, false
		}
		output = completed.data
	}
	fields := strings.Fields(string(output))
	if len(fields) == 0 {
		return 0, false
	}
	var sizeKB int64
	if _, err := fmt.Sscanf(fields[0], "%d", &sizeKB); err != nil {
		return 0, false
	}
	return sizeKB * 1024, true
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
	go h.pollServerTransferProgress(ctx, c, userID, fmt.Sprintf("%d", dstHost.ID), destMonitorPath, totalSize, isDir)

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

	return true, true
}

func destMonitorBaseName(resolvedSrc, destFileName string) string {
	if destFileName != "" {
		return path.Base(destFileName)
	}
	return path.Base(resolvedSrc)
}
