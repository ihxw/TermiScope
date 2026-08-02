package handlers

import (
	"fmt"
	"strings"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	termiscopeSSH "github.com/ihxw/termiscope/internal/ssh"
)

type hostConnector struct {
	encryptionKey      string
	timeout            time.Duration
	persistFingerprint func(*models.SSHHost) error
}

func newHostConnector(encryptionKey, timeoutText string, persistFingerprint func(*models.SSHHost) error) hostConnector {
	timeout, err := time.ParseDuration(timeoutText)
	if err != nil || timeout <= 0 {
		timeout = 30 * time.Second
	}
	return hostConnector{
		encryptionKey:      encryptionKey,
		timeout:            timeout,
		persistFingerprint: persistFingerprint,
	}
}

// open applies the shared credential, timeout, fingerprint, and TOFU policy.
// Authorization remains the responsibility of the calling adapter.
func (c hostConnector) open(host *models.SSHHost, insecure bool) (*termiscopeSSH.SSHClient, string, error) {
	password, privateKey := decryptHostCredentials(host, c.encryptionKey)
	if password == "" && privateKey == "" {
		return nil, "", fmt.Errorf("host has no credentials configured")
	}
	port := host.Port
	if port == 0 {
		port = 22
	}
	client, err := termiscopeSSH.NewSSHClient(&termiscopeSSH.SSHConfig{
		Host:               strings.Trim(host.Host, "[]"),
		Port:               port,
		Username:           host.Username,
		Password:           password,
		PrivateKey:         privateKey,
		Timeout:            c.timeout,
		Fingerprint:        host.Fingerprint,
		InsecureSkipVerify: insecure,
	})
	if err != nil {
		return nil, "", err
	}
	if err := client.Connect(); err != nil {
		return client, client.GetFingerprint(), err
	}

	observed := client.GetFingerprint()
	if !insecure && host.Fingerprint == "" && observed != "" {
		host.Fingerprint = observed
		if c.persistFingerprint != nil {
			if err := c.persistFingerprint(host); err != nil {
				_ = client.Close()
				return nil, observed, fmt.Errorf("persist host fingerprint: %w", err)
			}
		}
	}
	return client, observed, nil
}
