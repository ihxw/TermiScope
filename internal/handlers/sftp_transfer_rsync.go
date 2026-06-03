package handlers

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/ssh"
	"github.com/ihxw/termiscope/internal/utils"
	cryptossh "golang.org/x/crypto/ssh"
)

// rsyncProgressRe matches rsync --info=progress2 lines, e.g. "  1,234,567  45%  1.23MB/s ..."
var rsyncProgressRe = regexp.MustCompile(`(\d+)%\s+(\S+/s)`)

// directTransferAuth holds remote-shell credentials for source→dest transfers (rsync over SSH).
type directTransferAuth struct {
	rsyncPrefix string // optional "sshpass -f /path"
	sshForRsync string // ssh … flags for rsync -e
	cleanupCmd  string // remove temp key/password files
}

func remoteDestPath(destPath, destFileName string, isDir bool) string {
	return scpDestPath(destPath, destFileName, isDir)
}

func rsyncRemoteDest(username, host string, destPath, destFileName string, isDir bool) string {
	remote := remoteDestPath(destPath, destFileName, isDir)
	return fmt.Sprintf("%s@%s:%s", username, host, remote)
}

func (h *SftpHandler) remoteHasRsync(rawClient *cryptossh.Client) bool {
	session, err := rawClient.NewSession()
	if err != nil {
		return false
	}
	defer session.Close()
	_, err = session.Output("command -v rsync >/dev/null 2>&1")
	return err == nil
}

// buildRemoteRsyncInstallScript installs rsync when missing (runs on the source host over SSH).
func buildRemoteRsyncInstallScript() string {
	return `
if command -v rsync >/dev/null 2>&1; then
  exit 0
fi
run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n "$@"
  else
    return 127
  fi
}
if command -v apt-get >/dev/null 2>&1; then
  run apt-get update -qq 2>/dev/null || true
  run apt-get install -y rsync
elif command -v dnf >/dev/null 2>&1; then
  run dnf install -y rsync
elif command -v yum >/dev/null 2>&1; then
  run yum install -y rsync
elif command -v apk >/dev/null 2>&1; then
  run apk add --no-cache rsync
elif command -v zypper >/dev/null 2>&1; then
  run zypper -n install rsync
elif command -v pacman >/dev/null 2>&1; then
  run pacman -Sy --noconfirm rsync
else
  echo "TRANSFER_ERROR: unsupported package manager for automatic rsync install" >&2
  exit 1
fi
command -v rsync >/dev/null 2>&1
`
}

func (h *SftpHandler) ensureRemoteRsync(c *gin.Context, rawClient *cryptossh.Client) bool {
	if h.remoteHasRsync(rawClient) {
		return true
	}

	sendTransferEvent(c, map[string]interface{}{
		"type":    "info",
		"message": "rsync not found on source host, installing…",
	})

	session, err := rawClient.NewSession()
	if err != nil {
		return false
	}
	defer session.Close()

	combined, err := session.CombinedOutput(buildRemoteRsyncInstallScript())
	if err != nil {
		msg := strings.TrimSpace(string(combined))
		if msg == "" {
			msg = err.Error()
		}
		sendTransferEvent(c, map[string]interface{}{
			"type":    "info",
			"message": "failed to install rsync on source host: " + msg,
		})
		return false
	}

	if !h.remoteHasRsync(rawClient) {
		sendTransferEvent(c, map[string]interface{}{
			"type":    "info",
			"message": "rsync install finished but rsync is still unavailable on source host",
		})
		return false
	}

	sendTransferEvent(c, map[string]interface{}{
		"type":    "info",
		"message": "rsync installed on source host",
	})
	return true
}

func (h *SftpHandler) prepareDirectTransferAuth(
	c *gin.Context,
	rawClient *cryptossh.Client,
	dstHost models.SSHHost,
	dstPassword, dstPrivateKey string,
) (*directTransferAuth, bool) {
	port := dstHost.Port
	if port == 0 {
		port = 22
	}
	sshOptsBase := fmt.Sprintf("-p %d -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$TMP_HOSTS", port)

	if dstPrivateKey != "" {
		setupSession, err := rawClient.NewSession()
		if err != nil {
			return nil, false
		}
		escapedKey := strings.ReplaceAll(dstPrivateKey, "'", "'\\''")
		cmd := fmt.Sprintf("TMPKEY=$(mktemp /tmp/ts_key_XXXXXX) && chmod 600 $TMPKEY && printf '%%s' '%s' > $TMPKEY && echo $TMPKEY", escapedKey)
		output, err := setupSession.Output(cmd)
		setupSession.Close()
		if err != nil {
			return nil, false
		}
		tmpKeyPath := strings.TrimSpace(string(output))
		if tmpKeyPath == "" || !strings.HasPrefix(tmpKeyPath, "/tmp/ts_key_") {
			return nil, false
		}
		return &directTransferAuth{
			sshForRsync: fmt.Sprintf("ssh -i %s %s", utils.ShellEscape(tmpKeyPath), sshOptsBase),
			cleanupCmd:  fmt.Sprintf("rm -f %s", utils.ShellEscape(tmpKeyPath)),
		}, true
	}

	if dstPassword == "" {
		return nil, false
	}

	checkSession, err := rawClient.NewSession()
	if err != nil {
		return nil, false
	}
	_, err = checkSession.Output("command -v sshpass")
	checkSession.Close()
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "sshpass not available on source host, falling back to relay"})
		return nil, false
	}

	passSession, err := rawClient.NewSession()
	if err != nil {
		return nil, false
	}
	escapedPass := strings.ReplaceAll(dstPassword, "'", "'\\''")
	passCmd := fmt.Sprintf("TMPPASS=$(mktemp /tmp/ts_pass_XXXXXX) && chmod 600 $TMPPASS && printf '%%s' '%s' > $TMPPASS && echo $TMPPASS", escapedPass)
	passOutput, err := passSession.Output(passCmd)
	passSession.Close()
	if err != nil {
		return nil, false
	}
	tmpPassPath := strings.TrimSpace(string(passOutput))
	if tmpPassPath == "" || !strings.HasPrefix(tmpPassPath, "/tmp/ts_pass_") {
		return nil, false
	}

	return &directTransferAuth{
		rsyncPrefix: fmt.Sprintf("sshpass -f %s", utils.ShellEscape(tmpPassPath)),
		sshForRsync: fmt.Sprintf("ssh %s", sshOptsBase),
		cleanupCmd:  fmt.Sprintf("rm -f %s", utils.ShellEscape(tmpPassPath)),
	}, true
}

func buildHostKeyVerifyScript(dstHost models.SSHHost, cleanupCmd string) string {
	expectedFp := dstHost.Fingerprint
	if expectedFp != "" {
		expectedFpStr := strings.ReplaceAll(expectedFp, "'", "'\\''")
		return fmt.Sprintf(`
export TMP_HOSTS=$(mktemp /tmp/ts_hosts_XXXXXX)
ssh-keyscan -p %d %s > $TMP_HOSTS 2>/dev/null
SCANNED_FP=$(ssh-keygen -l -f $TMP_HOSTS 2>/dev/null | awk '{print $2}' | head -n 1)
if [ "$SCANNED_FP" != '%s' ]; then
	echo "TRANSFER_ERROR: destination host key fingerprint mismatch (expected '%s', got $SCANNED_FP)" >&2
	rm -f $TMP_HOSTS
	%s
	exit 1
fi`, dstHost.Port, utils.ShellEscape(dstHost.Host), expectedFpStr, expectedFpStr, cleanupCmd)
	}
	return fmt.Sprintf("export TMP_HOSTS=$(mktemp /tmp/ts_hosts_XXXXXX)\nssh-keyscan -p %d %s > $TMP_HOSTS 2>/dev/null", dstHost.Port, utils.ShellEscape(dstHost.Host))
}

func buildRsyncCommand(auth *directTransferAuth, dstHost models.SSHHost, sourcePath, destPath, destFileName string, isDir bool) string {
	destURI := rsyncRemoteDest(dstHost.Username, dstHost.Host, destPath, destFileName, isDir)
	sshE := auth.sshForRsync
	rsyncLine := fmt.Sprintf("%s rsync -a --info=progress2 --partial -e %s %s %s",
		auth.rsyncPrefix,
		utils.ShellEscape(sshE),
		utils.ShellEscape(sourcePath),
		utils.ShellEscape(destURI),
	)
	return strings.TrimSpace(rsyncLine)
}

func parseRsyncProgressLine(line string) (percent int, speed string, ok bool) {
	matches := rsyncProgressRe.FindStringSubmatch(line)
	if len(matches) < 3 {
		return 0, "", false
	}
	fmt.Sscanf(matches[1], "%d", &percent)
	return percent, matches[2], true
}

func streamRsyncProgress(r io.Reader, c *gin.Context) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	var lastPercent int
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, "TRANSFER_ERROR:") {
			sendTransferEvent(c, map[string]interface{}{"type": "error", "message": strings.TrimSpace(line)})
			continue
		}
		if pct, speed, ok := parseRsyncProgressLine(line); ok && pct != lastPercent {
			lastPercent = pct
			sendTransferEvent(c, map[string]interface{}{
				"type": "progress", "percent": pct, "speed": speed,
			})
		}
	}
}

// tryDirectRsync runs rsync on the source host to push data directly to the destination.
// Returns (attempted, success).
func (h *SftpHandler) tryDirectRsync(
	c *gin.Context,
	srcSSH *ssh.SSHClient,
	dstHost models.SSHHost,
	dstPassword, dstPrivateKey string,
	sourcePath, destPath, destFileName string,
	isDir bool,
) (attempted bool, success bool) {
	rawClient := srcSSH.GetRawClient()
	if !h.ensureRemoteRsync(c, rawClient) {
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "rsync unavailable on source host, falling back to relay"})
		return false, false
	}

	auth, ok := h.prepareDirectTransferAuth(c, rawClient, dstHost, dstPassword, dstPrivateKey)
	if !ok || auth == nil {
		return false, false
	}

	hostKeyScript := buildHostKeyVerifyScript(dstHost, auth.cleanupCmd)
	rsyncCmd := buildRsyncCommand(auth, dstHost, sourcePath, destPath, destFileName, isDir)
	fullCmd := fmt.Sprintf("%s\n%s\nrm -f $TMP_HOSTS\n%s",
		hostKeyScript,
		rsyncCmd,
		auth.cleanupCmd,
	)

	session, err := rawClient.NewSession()
	if err != nil {
		return false, false
	}
	defer session.Close()

	stderr, err := session.StderrPipe()
	if err != nil {
		return false, false
	}
	if err := session.Start(fullCmd); err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "rsync start failed: " + err.Error()})
		return true, false
	}

	streamRsyncProgress(stderr, c)

	exitErr := session.Wait()
	if exitErr != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "rsync failed: " + exitErr.Error()})
		return true, false
	}

	sendTransferEvent(c, map[string]interface{}{"type": "complete", "method": "rsync"})
	return true, true
}

func deleteRemotePathViaSSH(srcSSH *ssh.SSHClient, remotePath string) error {
	session, err := srcSSH.GetRawClient().NewSession()
	if err != nil {
		return err
	}
	defer session.Close()
	return session.Run("rm -rf " + utils.ShellEscape(remotePath))
}
