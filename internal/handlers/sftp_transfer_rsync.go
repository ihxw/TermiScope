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

func remoteDestPath(destPath, destFileName string, isDir, destIsDir bool) string {
	return scpDestPath(destPath, destFileName, isDir, destIsDir)
}

func rsyncRemoteDest(username, host string, destPath, destFileName string, isDir, destIsDir bool) string {
	remote := remoteDestPath(destPath, destFileName, isDir, destIsDir)
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

func (h *SftpHandler) ensureRemoteRsync(c *gin.Context, rawClient *cryptossh.Client) bool {
	if h.remoteHasRsync(rawClient) {
		return true
	}
	sendTransferEvent(c, map[string]interface{}{
		"type":    "info",
		"message": "rsync is not installed on the source host; using a non-invasive fallback",
	})
	return false
}

var ansiRegex = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

func extractPath(output, prefix string) string {
	cleanOutput := ansiRegex.ReplaceAllString(output, "")
	for _, field := range strings.Fields(cleanOutput) {
		if strings.HasPrefix(field, prefix) {
			return strings.TrimSpace(field)
		}
	}
	idx := strings.Index(cleanOutput, prefix)
	if idx != -1 {
		sub := cleanOutput[idx:]
		if endIdx := strings.IndexAny(sub, " \t\n\r"); endIdx != -1 {
			return sub[:endIdx]
		}
		return sub
	}
	return ""
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
			path := extractPath(string(output), "/tmp/ts_key_")
			if path != "" {
				if cleanSession, cleanErr := rawClient.NewSession(); cleanErr == nil {
					_ = cleanSession.Run(fmt.Sprintf("rm -f %s", utils.ShellEscape(path)))
					cleanSession.Close()
				}
			}
			return nil, false
		}
		tmpKeyPath := strings.TrimSpace(string(output))
		if tmpKeyPath == "" || !strings.HasPrefix(tmpKeyPath, "/tmp/ts_key_") {
			path := extractPath(string(output), "/tmp/ts_key_")
			if path != "" {
				if cleanSession, cleanErr := rawClient.NewSession(); cleanErr == nil {
					_ = cleanSession.Run(fmt.Sprintf("rm -f %s", utils.ShellEscape(path)))
					cleanSession.Close()
				}
			}
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
		path := extractPath(string(passOutput), "/tmp/ts_pass_")
		if path != "" {
			if cleanSession, cleanErr := rawClient.NewSession(); cleanErr == nil {
				_ = cleanSession.Run(fmt.Sprintf("rm -f %s", utils.ShellEscape(path)))
				cleanSession.Close()
			}
		}
		return nil, false
	}
	tmpPassPath := strings.TrimSpace(string(passOutput))
	if tmpPassPath == "" || !strings.HasPrefix(tmpPassPath, "/tmp/ts_pass_") {
		path := extractPath(string(passOutput), "/tmp/ts_pass_")
		if path != "" {
			if cleanSession, cleanErr := rawClient.NewSession(); cleanErr == nil {
				_ = cleanSession.Run(fmt.Sprintf("rm -f %s", utils.ShellEscape(path)))
				cleanSession.Close()
			}
		}
		return nil, false
	}

	return &directTransferAuth{
		rsyncPrefix: fmt.Sprintf("sshpass -f %s", utils.ShellEscape(tmpPassPath)),
		sshForRsync: fmt.Sprintf("ssh %s", sshOptsBase),
		cleanupCmd:  fmt.Sprintf("rm -f %s", utils.ShellEscape(tmpPassPath)),
	}, true
}

func buildHostKeyVerifyScript(dstHost models.SSHHost, tmpHostsPath, cleanupCmd string) string {
	expectedFp := dstHost.Fingerprint
	port := dstHost.Port
	if port == 0 {
		port = 22
	}
	escapedHostsPath := utils.ShellEscape(tmpHostsPath)
	if expectedFp != "" {
		expectedFpStr := strings.ReplaceAll(expectedFp, "'", "'\\''")
		return fmt.Sprintf(`
export TMP_HOSTS=%s
ssh-keyscan -p %d %s > $TMP_HOSTS 2>/dev/null
SCANNED_FP=$(ssh-keygen -l -f $TMP_HOSTS 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ',')
if ! ssh-keygen -l -f $TMP_HOSTS 2>/dev/null | awk '{print $2}' | grep -Fx -- '%s' >/dev/null; then
	echo "TRANSFER_ERROR: destination host key fingerprint mismatch (expected '%s', got $SCANNED_FP)" >&2
	rm -f $TMP_HOSTS
	%s
	exit 1
fi`, escapedHostsPath, port, utils.ShellEscape(dstHost.Host), expectedFpStr, expectedFpStr, cleanupCmd)
	}
	return fmt.Sprintf("echo 'TRANSFER_ERROR: destination host has no trusted fingerprint' >&2\n%s\nexit 1", cleanupCmd)
}

func buildRsyncCommand(auth *directTransferAuth, dstHost models.SSHHost, sourcePath, destPath, destFileName string, isDir, destIsDir bool) string {
	destURI := rsyncRemoteDest(dstHost.Username, dstHost.Host, destPath, destFileName, isDir, destIsDir)
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
			sendTransferEvent(c, map[string]interface{}{"type": "info", "message": strings.TrimSpace(line)})
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
	destIsDir bool,
) (attempted bool, success bool) {
	tmpHostsPath := fmt.Sprintf("/tmp/ts_hosts_%s", utils.GenerateRandomString(12))

	rawClient := srcSSH.GetRawClient()
	if !h.ensureRemoteRsync(c, rawClient) {
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "rsync unavailable on source host, falling back to relay"})
		return false, false
	}

	auth, ok := h.prepareDirectTransferAuth(c, rawClient, dstHost, dstPassword, dstPrivateKey)
	if !ok || auth == nil {
		return false, false
	}
	defer func() {
		if auth != nil && auth.cleanupCmd != "" {
			cleanupSession, err := rawClient.NewSession()
			if err == nil {
				_ = cleanupSession.Run(auth.cleanupCmd)
				cleanupSession.Close()
			}
		}
		cleanupHostsSession, err := rawClient.NewSession()
		if err == nil {
			_ = cleanupHostsSession.Run(fmt.Sprintf("rm -f %s", utils.ShellEscape(tmpHostsPath)))
			cleanupHostsSession.Close()
		}
	}()

	hostKeyScript := buildHostKeyVerifyScript(dstHost, tmpHostsPath, auth.cleanupCmd)
	rsyncCmd := buildRsyncCommand(auth, dstHost, sourcePath, destPath, destFileName, isDir, destIsDir)
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
	ctx := c.Request.Context()
	doneChan := make(chan struct{})
	defer close(doneChan)

	go func() {
		select {
		case <-ctx.Done():
			session.Close()
		case <-doneChan:
		}
	}()

	if err := session.Start(fullCmd); err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "rsync start failed, falling back: " + err.Error()})
		return true, false
	}

	streamRsyncProgress(stderr, c)

	exitErr := session.Wait()
	if exitErr != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "rsync failed, falling back: " + exitErr.Error()})
		return true, false
	}

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
