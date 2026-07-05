package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	_ "modernc.org/sqlite"
)

func openSystemSettingsTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsnName := strings.NewReplacer("/", "_", " ", "_").Replace(t.Name())
	db, err := gorm.Open(sqlite.Dialector{
		DriverName: "sqlite",
		DSN:        "file:" + dsnName + "?mode=memory&cache=shared&_time_format=sqlite",
	}, &gorm.Config{})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	if err := db.AutoMigrate(&models.SystemConfig{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func newSystemSettingsTestHandler(db *gorm.DB) *SystemHandler {
	return NewSystemHandler(db, &config.Config{
		Server: config.ServerConfig{
			Timezone: "Local",
		},
		SSH: config.SSHConfig{
			Timeout:               "30s",
			IdleTimeout:           "30m",
			MaxConnectionsPerUser: 10,
		},
		Security: config.SecurityConfig{
			EncryptionKey:     "0123456789abcdef0123456789abcdef",
			LoginRateLimit:    20,
			AccessExpiration:  "60m",
			RefreshExpiration: "168h",
		},
	}, "test")
}

func runSystemJSONRequest(handler gin.HandlerFunc, method, path string, body any) *httptest.ResponseRecorder {
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

func TestUpdateSettingsAcceptsStringSMTPSkipVerify(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db := openSystemSettingsTestDB(t)
	handler := newSystemSettingsTestHandler(db)

	w := runSystemJSONRequest(handler.UpdateSettings, http.MethodPut, "/api/system/settings", gin.H{
		"timezone":                 "Local",
		"ssh_timeout":              "30s",
		"idle_timeout":             "30m",
		"max_connections_per_user": 10,
		"login_rate_limit":         20,
		"access_expiration":        "60m",
		"refresh_expiration":       "168h",
		"smtp_tls_skip_verify":     "false",
	})

	if w.Code != http.StatusOK {
		t.Fatalf("status=%d want %d body=%s", w.Code, http.StatusOK, w.Body.String())
	}

	var stored models.SystemConfig
	if err := db.Where("config_key = ?", "smtp_tls_skip_verify").First(&stored).Error; err != nil {
		t.Fatalf("load smtp_tls_skip_verify: %v", err)
	}
	if stored.ConfigValue != "false" {
		t.Fatalf("stored smtp_tls_skip_verify=%q want false", stored.ConfigValue)
	}
}
