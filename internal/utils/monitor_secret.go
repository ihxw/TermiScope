package utils

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"io"
)

func GenerateMonitorSecret() (string, error) {
	buffer := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, buffer); err != nil {
		return "", err
	}
	return hex.EncodeToString(buffer), nil
}

// MonitorSecretEqual compares agent monitor secrets in constant time.
func MonitorSecretEqual(stored, provided string) bool {
	if stored == "" || provided == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(stored), []byte(provided)) == 1
}
