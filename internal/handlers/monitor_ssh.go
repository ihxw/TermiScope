package handlers

import (
	"fmt"
	"strings"

	"github.com/ihxw/termiscope/internal/models"
	"golang.org/x/crypto/ssh"
)

// openMonitorSSH opens an SSH connection for monitor deploy/stop using TOFU or stored fingerprint.
// When insecure is true, host key verification is skipped (batch deploy legacy option).
func openMonitorSSH(host *models.SSHHost, encryptionKey string, insecure bool) (*ssh.Client, string, error) {
	client, observed, err := newHostConnector(encryptionKey, "30s", nil).open(host, insecure)
	if err != nil {
		return nil, observed, err
	}
	return client.GetRawClient(), observed, nil
}

func monitorSSHDialAddr(host *models.SSHHost) string {
	cleanHost := strings.Trim(host.Host, "[]")
	return fmt.Sprintf("%s:%d", cleanHost, host.Port)
}
