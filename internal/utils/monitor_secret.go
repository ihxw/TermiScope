package utils

import "crypto/subtle"

// MonitorSecretEqual compares agent monitor secrets in constant time.
func MonitorSecretEqual(stored, provided string) bool {
	if stored == "" || provided == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(stored), []byte(provided)) == 1
}
