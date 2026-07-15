package utils

import (
	cryptorand "crypto/rand"
	"math/rand"
	"sync"
	"time"
)

const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

var seededRand *rand.Rand = rand.New(rand.NewSource(time.Now().UnixNano()))
var seededRandMu sync.Mutex

// GenerateRandomString generates a random string of fixed length
func GenerateRandomString(length int) string {
	b := make([]byte, length)
	random := make([]byte, length*2+16)
	written := 0
	for written < length {
		if _, err := cryptorand.Read(random); err != nil {
			seededRandMu.Lock()
			for i := written; i < length; i++ {
				b[i] = charset[seededRand.Intn(len(charset))]
			}
			seededRandMu.Unlock()
			break
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
