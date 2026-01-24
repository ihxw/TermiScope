package ssh

import (
	"fmt"
	"net"
	"strconv"
	"time"

	"golang.org/x/crypto/ssh"
)

type SSHClient struct {
	client      *ssh.Client
	session     *ssh.Session
	config      *ssh.ClientConfig
	host        string
	port        int
	fingerprint string
}

type SSHConfig struct {
	Host        string
	Port        int
	Username    string
	Password    string
	PrivateKey  string
	Timeout     time.Duration
	Fingerprint string // Expected fingerprint (empty for TOFU)
}

// NewSSHClient creates a new SSH client
// NewSSHClient creates a new SSH client
func NewSSHClient(cfg *SSHConfig) (*SSHClient, error) {
	var authMethods []ssh.AuthMethod

	// Add password authentication
	if cfg.Password != "" {
		authMethods = append(authMethods, ssh.Password(cfg.Password))
	}

	// Add key authentication
	if cfg.PrivateKey != "" {
		signer, err := ssh.ParsePrivateKey([]byte(cfg.PrivateKey))
		if err != nil {
			return nil, fmt.Errorf("failed to parse private key: %w", err)
		}
		authMethods = append(authMethods, ssh.PublicKeys(signer))
	}

	if len(authMethods) == 0 {
		return nil, fmt.Errorf("no authentication method provided")
	}

	client := &SSHClient{
		host: cfg.Host,
		port: cfg.Port,
	}

	// Host Key Verification Callback
	hostKeyCallback := func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		// Calculate fingerprint
		fp := ssh.FingerprintSHA256(key)
		client.fingerprint = fp

		if cfg.Fingerprint == "" {
			// TOFU: Trust On First Use
			return nil
		}

		if fp != cfg.Fingerprint {
			return fmt.Errorf("host key fingerprint mismatch: anticipated %s, got %s", cfg.Fingerprint, fp)
		}

		return nil
	}

	config := &ssh.ClientConfig{
		User:            cfg.Username,
		Auth:            authMethods,
		HostKeyCallback: hostKeyCallback,
		Timeout:         cfg.Timeout,
	}

	client.config = config
	return client, nil
}

// Connect establishes the SSH connection
func (c *SSHClient) Connect() error {
	addr := net.JoinHostPort(c.host, strconv.Itoa(c.port))
	client, err := ssh.Dial("tcp", addr, c.config)
	if err != nil {
		return fmt.Errorf("failed to dial: %w", err)
	}

	c.client = client
	return nil
}

// NewSession creates a new SSH session
func (c *SSHClient) NewSession() error {
	if c.client == nil {
		return fmt.Errorf("not connected")
	}

	session, err := c.client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create session: %w", err)
	}

	c.session = session
	return nil
}

// RequestPTY requests a pseudo-terminal
func (c *SSHClient) RequestPTY(term string, height, width int) error {
	if c.session == nil {
		return fmt.Errorf("no session")
	}

	modes := ssh.TerminalModes{
		ssh.ECHO:          1,
		ssh.TTY_OP_ISPEED: 14400,
		ssh.TTY_OP_OSPEED: 14400,
	}

	if err := c.session.RequestPty(term, height, width, modes); err != nil {
		return fmt.Errorf("failed to request PTY: %w", err)
	}

	return nil
}

// Shell starts an interactive shell
func (c *SSHClient) Shell() error {
	if c.session == nil {
		return fmt.Errorf("no session")
	}

	if err := c.session.Shell(); err != nil {
		return fmt.Errorf("failed to start shell: %w", err)
	}

	return nil
}

// Resize resizes the terminal
func (c *SSHClient) Resize(height, width int) error {
	if c.session == nil {
		return fmt.Errorf("no session")
	}

	return c.session.WindowChange(height, width)
}

// Close closes the SSH connection
func (c *SSHClient) Close() error {
	if c.session != nil {
		c.session.Close()
	}
	if c.client != nil {
		return c.client.Close()
	}
	return nil
}

// GetSession returns the SSH session
func (c *SSHClient) GetSession() *ssh.Session {
	return c.session
}

// GetRawClient returns the underlying ssh.Client
func (c *SSHClient) GetRawClient() *ssh.Client {
	return c.client
}

// Wait waits for the session to finish
func (c *SSHClient) Wait() error {
	if c.session == nil {
		return fmt.Errorf("no session")
	}
	return c.session.Wait()
}

// SendKeepAlive sends a keep-alive message
func (c *SSHClient) SendKeepAlive() error {
	if c.client == nil {
		return fmt.Errorf("not connected")
	}

	_, _, err := c.client.SendRequest("keepalive@openssh.com", true, nil)
	return err
}

// IsConnected checks if the connection is still alive
func (c *SSHClient) IsConnected() bool {
	if c.client == nil {
		return false
	}

	// Try to send a keep-alive message
	err := c.SendKeepAlive()
	return err == nil
}

// GetFingerprint returns the host key fingerprint
func (c *SSHClient) GetFingerprint() string {
	// If already connected, we might want to get it from the active session?
	// But our callback logic stores it in the struct.
	// Since HostKeyCallback is called during Dial, we need to ensure the value is captured.
	// In the closure we updated a local variable 'fingerprint', we need to ensure that updates c.fingerprint.
	// Actually, the closure runs BEFORE NewSSHClient returns if we call Dial inside NewSSHClient? No, Dial is called in Connect().
	// So we need to refactor slightly to capture the fingerprint properly.
	return c.fingerprint
}
