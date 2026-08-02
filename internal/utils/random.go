package utils

import (
	cryptorand "crypto/rand"
	"fmt"
)

const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

// GenerateRandomString generates a random string of fixed length
func GenerateRandomString(length int) string {
	b := make([]byte, length)
	random := make([]byte, length*2+16)
	written := 0
	for written < length {
		if _, err := cryptorand.Read(random); err != nil {
			panic(fmt.Sprintf("secure random source unavailable: %v", err))
		}
		for _, value := range random {
			// Reject the modulo tail to keep the character distribution uniform.
			if int(value) >= 256-(256%len(charset)) {
				continue
			}
			b[written] = charset[int(value)%len(charset)]
			written++
			if written == length {
				break
			}
		}
	}
	return string(b)
}
