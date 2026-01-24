package utils

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"os"

	"golang.org/x/crypto/pbkdf2"
)

// EncryptAES encrypts plaintext using AES-256-GCM
func EncryptAES(plaintext string, key string) (string, error) {
	if plaintext == "" {
		return "", nil
	}

	keyBytes := []byte(key)
	plaintextBytes := []byte(plaintext)

	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return "", fmt.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("failed to create GCM: %w", err)
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("failed to generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nonce, nonce, plaintextBytes, nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// DecryptAES decrypts ciphertext using AES-256-GCM
func DecryptAES(ciphertext string, key string) (string, error) {
	if ciphertext == "" {
		return "", nil
	}

	keyBytes := []byte(key)
	ciphertextBytes, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", fmt.Errorf("failed to decode ciphertext: %w", err)
	}

	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return "", fmt.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("failed to create GCM: %w", err)
	}

	nonceSize := gcm.NonceSize()
	if len(ciphertextBytes) < nonceSize {
		return "", fmt.Errorf("ciphertext too short")
	}

	nonce, ciphertextBytes := ciphertextBytes[:nonceSize], ciphertextBytes[nonceSize:]
	plaintext, err := gcm.Open(nil, nonce, ciphertextBytes, nil)
	if err != nil {
		return "", fmt.Errorf("failed to decrypt: %w", err)
	}

	return string(plaintext), nil
}

// GenerateRandomKey generates a random key of specified size
func GenerateRandomKey(size int) (string, error) {
	key := make([]byte, size)
	if _, err := rand.Read(key); err != nil {
		return "", fmt.Errorf("failed to generate random key: %w", err)
	}
	return base64.StdEncoding.EncodeToString(key), nil
}

// Encrypt is an alias for EncryptAES
func Encrypt(plaintext string, key string) (string, error) {
	return EncryptAES(plaintext, key)
}

// Decrypt is an alias for DecryptAES
func Decrypt(ciphertext string, key string) (string, error) {
	return DecryptAES(ciphertext, key)
}

// DeriveKey derives a 32-byte key from password and salt using PBKDF2
func DeriveKey(password string, salt []byte) []byte {
	return pbkdf2.Key([]byte(password), salt, 4096, 32, sha256.New)
}

// EncryptFile encrypts a file using AES-GCM with a password-derived key
func EncryptFile(srcPath, dstPath, password string) error {
	srcFile, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	dstFile, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	// Generate salt
	salt := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return err
	}

	// Write salt to output file
	if _, err := dstFile.Write(salt); err != nil {
		return err
	}

	// Derive key
	key := DeriveKey(password, salt)

	// Create cipher
	block, err := aes.NewCipher(key)
	if err != nil {
		return err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}

	// Generate nonce
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return err
	}

	// Write nonce to output file
	if _, err := dstFile.Write(nonce); err != nil {
		return err
	}

	// We'll read the whole file for simplicity as GCM is authenticated and needs whole block
	// For very large files, chunking with stream encryption is better, but GCM works on blocks.
	// Loading standard backup files (MBs) into RAM is usually acceptable.
	plaintext, err := io.ReadAll(srcFile)
	if err != nil {
		return err
	}

	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)
	if _, err := dstFile.Write(ciphertext); err != nil {
		return err
	}

	return nil
}

// DecryptFile decrypts a file using AES-GCM with a password-derived key
func DecryptFile(srcPath, dstPath, password string) error {
	srcFile, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	// Read salt
	salt := make([]byte, 16)
	if _, err := io.ReadFull(srcFile, salt); err != nil {
		return fmt.Errorf("failed to read salt: %w", err)
	}

	// Derive key
	key := DeriveKey(password, salt)

	// Create cipher
	block, err := aes.NewCipher(key)
	if err != nil {
		return err
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}

	// Read nonce
	nonceSize := gcm.NonceSize()
	nonce := make([]byte, nonceSize)
	if _, err := io.ReadFull(srcFile, nonce); err != nil {
		return fmt.Errorf("failed to read nonce: %w", err)
	}

	// Read remaining ciphertext
	ciphertext, err := io.ReadAll(srcFile)
	if err != nil {
		return err
	}

	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return fmt.Errorf("decryption failed (wrong password?): %w", err)
	}

	dstFile, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	if _, err := dstFile.Write(plaintext); err != nil {
		return err
	}

	return nil
}
