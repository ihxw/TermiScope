package utils

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	UserID    uint   `json:"user_id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	TokenType string `json:"token_type"` // "access" or "refresh"
	jwt.RegisteredClaims
}

// GenerateToken generates a JWT token for a user
func GenerateToken(userID uint, username, role, tokenType string, expiration time.Duration, secret string) (string, error) {
	claims := &Claims{
		UserID:    userID,
		Username:  username,
		Role:      role,
		TokenType: tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(expiration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", fmt.Errorf("failed to sign token: %w", err)
	}

	return tokenString, nil
}

// ValidateToken validates a JWT token and returns the claims
func ValidateToken(tokenString, secret string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(secret), nil
	})

	if err != nil {
		// Check if the error is due to token expiration
		if err == jwt.ErrTokenExpired {
			return nil, fmt.Errorf("token expired: %w", err)
		}
		// Provide more detailed error information
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	// If we got here, the token is structurally valid but failed validation
	// This could be due to expiration or other claim validation failures
	if claims, ok := token.Claims.(*Claims); ok {
		// Check if token is expired
		if claims.ExpiresAt != nil && claims.ExpiresAt.Time.Before(time.Now()) {
			return nil, fmt.Errorf("token expired at %s (current time: %s)",
				claims.ExpiresAt.Time.Format(time.RFC3339),
				time.Now().Format(time.RFC3339))
		}
	}

	return nil, fmt.Errorf("invalid token")
}
