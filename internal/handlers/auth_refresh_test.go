package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	_ "modernc.org/sqlite"
)

func openAuthTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsnName := strings.NewReplacer("/", "_", " ", "_").Replace(t.Name())
	db, err := gorm.Open(sqlite.Dialector{
		DriverName: "sqlite",
		DSN:        "file:" + dsnName + "?mode=memory&cache=shared&_time_format=sqlite",
	}, &gorm.Config{})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	if err := db.AutoMigrate(&models.User{}, &models.LoginHistory{}, &models.RevokedToken{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func newAuthTestHandler(db *gorm.DB) *AuthHandler {
	return NewAuthHandler(db, &config.Config{
		Security: config.SecurityConfig{
			JWTSecret:         "0123456789abcdef0123456789abcdef",
			EncryptionKey:     "0123456789abcdef0123456789abcdef",
			AccessExpiration:  "15m",
			RefreshExpiration: "24h",
		},
	})
}

func runAuthJSONRequest(handler gin.HandlerFunc, method, path string, body any) *httptest.ResponseRecorder {
	var reqBody bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&reqBody).Encode(body); err != nil {
			panic(err)
		}
	}
	req := httptest.NewRequest(method, path, &reqBody)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	handler(c)
	return w
}

func decodeAuthSuccessData(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var resp struct {
		Success bool           `json:"success"`
		Data    map[string]any `json:"data"`
		Error   string         `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v\nbody: %s", err, w.Body.String())
	}
	if !resp.Success {
		t.Fatalf("response failed: status=%d error=%q body=%s", w.Code, resp.Error, w.Body.String())
	}
	return resp.Data
}

func TestRefreshTokenRotatesSessionHistory(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db := openAuthTestDB(t)
	handler := newAuthTestHandler(db)

	user := models.User{
		Username:    "alice",
		Email:       "alice@example.com",
		DisplayName: "Alice",
		Role:        "user",
		Status:      "active",
	}
	if err := user.SetPassword("password123"); err != nil {
		t.Fatalf("set password: %v", err)
	}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}

	login := runAuthJSONRequest(handler.Login, http.MethodPost, "/api/auth/login", gin.H{
		"username": "alice",
		"password": "password123",
	})
	if login.Code != http.StatusOK {
		t.Fatalf("login status=%d body=%s", login.Code, login.Body.String())
	}

	var history models.LoginHistory
	if err := db.Where("user_id = ?", user.ID).First(&history).Error; err != nil {
		t.Fatalf("load login history: %v", err)
	}
	oldAccessJTI := history.JTI
	oldRefreshJTI := history.RefreshTokenJTI
	if oldAccessJTI == "" || oldRefreshJTI == "" {
		t.Fatalf("login history missing initial JTIs: access=%q refresh=%q", oldAccessJTI, oldRefreshJTI)
	}

	var refreshCookie *http.Cookie
	for _, cookie := range login.Result().Cookies() {
		if cookie.Name == "refresh_token" {
			refreshCookie = cookie
			break
		}
	}
	if refreshCookie == nil || refreshCookie.Value == "" {
		t.Fatalf("login response did not set refresh_token cookie")
	}

	refresh := runAuthJSONRequest(handler.RefreshToken, http.MethodPost, "/api/auth/refresh", gin.H{
		"refresh_token": refreshCookie.Value,
	})
	if refresh.Code != http.StatusOK {
		t.Fatalf("refresh status=%d body=%s", refresh.Code, refresh.Body.String())
	}
	data := decodeAuthSuccessData(t, refresh)
	newAccessToken, ok := data["token"].(string)
	if !ok || newAccessToken == "" {
		t.Fatalf("refresh response missing token: %#v", data)
	}
	newAccessClaims, err := utils.ValidateToken(newAccessToken, handler.config.Security.JWTSecret)
	if err != nil {
		t.Fatalf("validate refreshed access token: %v", err)
	}

	var newRefreshToken string
	for _, cookie := range refresh.Result().Cookies() {
		if cookie.Name == "refresh_token" {
			newRefreshToken = cookie.Value
			break
		}
	}
	if newRefreshToken == "" {
		t.Fatalf("refresh response did not rotate refresh_token cookie")
	}
	newRefreshClaims, err := utils.ValidateToken(newRefreshToken, handler.config.Security.JWTSecret)
	if err != nil {
		t.Fatalf("validate refreshed refresh token: %v", err)
	}

	if err := db.First(&history, history.ID).Error; err != nil {
		t.Fatalf("reload login history: %v", err)
	}
	if history.JTI != newAccessClaims.ID {
		t.Fatalf("login history access JTI = %q, want refreshed access JTI %q", history.JTI, newAccessClaims.ID)
	}
	if history.RefreshTokenJTI != newRefreshClaims.ID {
		t.Fatalf("login history refresh JTI = %q, want refreshed refresh JTI %q", history.RefreshTokenJTI, newRefreshClaims.ID)
	}
	if history.JTI == oldAccessJTI || history.RefreshTokenJTI == oldRefreshJTI {
		t.Fatalf("login history still points at old session tokens")
	}
	if history.ExpiresAt == nil || time.Until(*history.ExpiresAt) <= 0 {
		t.Fatalf("login history expiration was not updated: %#v", history.ExpiresAt)
	}

	var revoked models.RevokedToken
	if err := db.Where("jti = ?", oldRefreshJTI).First(&revoked).Error; err != nil {
		t.Fatalf("old refresh token was not revoked: %v", err)
	}
}
