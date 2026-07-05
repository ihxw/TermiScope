package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestCORSAllowsSameOriginPostWithEmptyAllowlist(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name   string
		origin string
		host   string
	}{
		{
			name:   "localhost install",
			origin: "http://localhost:3000",
			host:   "localhost:3000",
		},
		{
			name:   "local IP install",
			origin: "http://192.168.1.20:3000",
			host:   "192.168.1.20:3000",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.Use(CORS(nil, false))
			router.POST("/api/auth/initialize", func(c *gin.Context) {
				c.JSON(http.StatusOK, gin.H{"ok": true})
			})

			req := httptest.NewRequest(http.MethodPost, "http://"+tt.host+"/api/auth/initialize", strings.NewReader(`{}`))
			req.Host = tt.host
			req.Header.Set("Origin", tt.origin)
			req.Header.Set("Content-Type", "application/json")

			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
			}
			if got := w.Header().Get("Access-Control-Allow-Origin"); got != tt.origin {
				t.Fatalf("Access-Control-Allow-Origin = %q, want %q", got, tt.origin)
			}
		})
	}
}
