package agenttransfer

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

const (
	CommandName              = "transfer"
	ConfigurePortCommandName = "configure_transfer_port"
	DefaultTransferPort      = 61725
	ModeDirect               = "direct"
	ModeRelaySource          = "relay_source"
	ModeRelayDest            = "relay_destination"
	RelayChunkSize           = 8 * 1024 * 1024
)

type ConfigurePortCommand struct {
	Port int `json:"port"`
}

type Command struct {
	Mode             string `json:"mode"`
	TransferID       string `json:"transfer_id"`
	SourceURL        string `json:"source_url"`
	SourceToken      string `json:"source_token"`
	SourceCertSHA256 string `json:"source_cert_sha256"`
	SourcePath       string `json:"source_path"`
	DestPath         string `json:"dest_path"`
	IsDir            bool   `json:"is_dir"`
	TotalSize        int64  `json:"total_size"`
}

type Report struct {
	TransferID  string  `json:"transfer_id"`
	Status      string  `json:"status"`
	Message     string  `json:"message,omitempty"`
	Transferred int64   `json:"transferred,omitempty"`
	Total       int64   `json:"total,omitempty"`
	Speed       float64 `json:"speed,omitempty"`
}

type SourceClaims struct {
	Path      string `json:"path"`
	IsDir     bool   `json:"is_dir"`
	ExpiresAt int64  `json:"expires_at"`
	Nonce     string `json:"nonce"`
}

func SignSourceToken(secret string, claims SourceClaims) (string, error) {
	if secret == "" || claims.Path == "" || claims.ExpiresAt <= time.Now().Unix() {
		return "", errors.New("invalid source token claims")
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(encoded))
	signature := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return encoded + "." + signature, nil
}

func VerifySourceToken(secret, token string, now time.Time) (SourceClaims, error) {
	var claims SourceClaims
	parts := strings.Split(token, ".")
	if secret == "" || len(parts) != 2 {
		return claims, errors.New("invalid source token")
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(parts[0]))
	provided, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || !hmac.Equal(provided, mac.Sum(nil)) {
		return claims, errors.New("invalid source token signature")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil || json.Unmarshal(payload, &claims) != nil {
		return SourceClaims{}, errors.New("invalid source token payload")
	}
	if claims.Path == "" || claims.Nonce == "" || now.Unix() >= claims.ExpiresAt {
		return SourceClaims{}, errors.New("source token expired")
	}
	return claims, nil
}

func NormalizeCertificateFingerprint(value string) (string, bool) {
	value = strings.ToLower(strings.TrimSpace(strings.ReplaceAll(value, ":", "")))
	decoded, err := hex.DecodeString(value)
	return value, err == nil && len(decoded) == sha256.Size
}
