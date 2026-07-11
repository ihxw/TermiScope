package utils

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"log"
	"net"
	"time"

	"golang.org/x/crypto/ssh"
	"gorm.io/gorm"
)

// SSHKeyVerifier handles SSH host key verification with TOFU strategy
type SSHKeyVerifier struct {
	savedFingerprint string
	hostID           uint
	db               *gorm.DB
	onNewFingerprint func(fingerprint string) error
}

// NewSSHKeyVerifier creates a new verifier
func NewSSHKeyVerifier(db *gorm.DB, hostID uint, savedFingerprint string, onNewFingerprint func(string) error) *SSHKeyVerifier {
	return &SSHKeyVerifier{
		savedFingerprint: savedFingerprint,
		hostID:           hostID,
		db:               db,
		onNewFingerprint: onNewFingerprint,
	}
}

// HostKeyCallback returns an ssh.HostKeyCallback for TOFU verification
func (v *SSHKeyVerifier) HostKeyCallback() ssh.HostKeyCallback {
	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		// Calculate fingerprint
		fingerprint := ssh.FingerprintSHA256(key)

		// If we have a saved fingerprint, verify it matches
		if v.savedFingerprint != "" {
			if fingerprint != v.savedFingerprint {
				// 记录安全事件
				logSecurityEvent(v.db, "SSH_HOST_KEY_MISMATCH", "CRITICAL",
					v.hostID, "", "", "",
					fmt.Sprintf("主机密钥指纹不匹配！期望：%s, 实际：%s", v.savedFingerprint, fingerprint),
					map[string]interface{}{
						"host_id":         v.hostID,
						"expected_fp":     v.savedFingerprint,
						"actual_fp":       fingerprint,
						"remote_addr":     remote.String(),
						"hostname":        hostname,
					})
				
				return fmt.Errorf("⚠️ 主机密钥指纹不匹配！可能的中间人攻击。\n期望的指纹：%s\n实际的指纹：%s",
					v.savedFingerprint, fingerprint)
			}
			return nil
		}

		// First time connection - save fingerprint (TOFU)
		if v.onNewFingerprint != nil {
			if err := v.onNewFingerprint(fingerprint); err != nil {
				return fmt.Errorf("保存主机密钥指纹失败：%w", err)
			}
			// 记录新主机密钥保存事件
			logSecurityEvent(v.db, "LOGIN_SUCCESS", "LOW",
				v.hostID, "", "", "",
				fmt.Sprintf("首次连接并保存主机密钥指纹：%s", fingerprint),
				map[string]interface{}{
					"host_id":   v.hostID,
					"fingerprint": fingerprint,
					"remote_addr": remote.String(),
				})
		}

		return nil
	}
}

// GetFingerprintFromKey extracts fingerprint from a public key
func GetFingerprintFromKey(key ssh.PublicKey) string {
	hash := sha256.Sum256(key.Marshal())
	return "SHA256:" + base64.StdEncoding.EncodeToString(hash[:])
}

// CreateSSHConfigWithVerification creates SSH config with host key verification
func CreateSSHConfigWithVerification(db *gorm.DB, hostID uint, username string, 
	authMethods []ssh.AuthMethod, savedFingerprint string, 
	onNewFingerprint func(fp string) error, timeout time.Duration) (*ssh.ClientConfig, error) {
	
	verifier := NewSSHKeyVerifier(db, hostID, savedFingerprint, onNewFingerprint)
	
	config := &ssh.ClientConfig{
		User:            username,
		Auth:            authMethods,
		HostKeyCallback: verifier.HostKeyCallback(),
		Timeout:         timeout,
		HostKeyAlgorithms: []string{
			ssh.KeyAlgoED25519,
			ssh.KeyAlgoECDSA256,
			ssh.KeyAlgoRSASHA512,
			ssh.KeyAlgoRSASHA256,
		},
	}
	
	return config, nil
}

// logSecurityEvent is a helper to log security events without circular dependency
func logSecurityEvent(db *gorm.DB, eventType, severity string, userID uint, username, ip, ua, details string, metadata map[string]interface{}) {
	// 简单实现，避免循环依赖
	// 完整实现需要在 models 包中
	log.Printf("[SECURITY] [%s] %s - User: %d, IP: %s, Details: %s", 
		severity, eventType, userID, ip, details)
}
