package handlers

import (
	"fmt"
	"strings"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	termiscopeSSH "github.com/ihxw/termiscope/internal/ssh"
	"golang.org/x/crypto/ssh"
)

// openMonitorSSH opens an SSH connection for monitor deploy/stop using TOFU or stored fingerprint.
// When insecure is true, host key verification is skipped (batch deploy legacy option).
func openMonitorSSH(host *models.SSHHost, encryptionKey string, insecure bool) (*ssh.Client, string, error) {
	password, privateKey := decryptHostCredentials(host, encryptionKey)

	timeout, _ := time.ParseDuration("30s")
	if timeout == 0 {
		timeout = 10 * time.Second
	}

	cleanHost := strings.Trim(host.Host, "[]")
	client, err := termiscopeSSH.NewSSHClient(&termiscopeSSH.SSHConfig{
		Host:               cleanHost,
		Port:               host.Port,
		Username:           host.Username,
		Password:           password,
		PrivateKey:         privateKey,
		Timeout:            timeout,
		Fingerprint:        host.Fingerprint,
		InsecureSkipVerify: insecure,
	})
	if err != nil {
		return nil, "", err
	}

	if err := client.Connect(); err != nil {
		return nil, client.GetFingerprint(), err
	}

	newFp := client.GetFingerprint()
	if !insecure && host.Fingerprint == "" && newFp != "" {
		host.Fingerprint = newFp
	}

	return client.GetRawClient(), newFp, nil
}

func monitorSSHDialAddr(host *models.SSHHost) string {
	cleanHost := strings.Trim(host.Host, "[]")
	return fmt.Sprintf("%s:%d", cleanHost, host.Port)
}
