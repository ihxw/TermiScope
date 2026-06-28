package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func setupSftpBookmarksTest(t *testing.T) (*gorm.DB, *SftpHandler) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if err := db.AutoMigrate(&models.SSHHost{}, &models.SftpPathBookmark{}); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db, &SftpHandler{db: db}
}

func runSftpBookmarkRequest(handler gin.HandlerFunc, userID uint, method, path string, body any) *httptest.ResponseRecorder {
	var reqBody bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&reqBody).Encode(body)
	}
	req := httptest.NewRequest(method, path, &reqBody)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	c.Params = gin.Params{{Key: "hostId", Value: "1"}}
	c.Set("user_id", userID)
	handler(c)
	return w
}

func TestSftpPathBookmarksSaveAndGet(t *testing.T) {
	db, handler := setupSftpBookmarksTest(t)
	if err := db.Create(&models.SSHHost{ID: 1, UserID: 10, Name: "host", Host: "127.0.0.1", Username: "root", AuthType: "password"}).Error; err != nil {
		t.Fatalf("create host: %v", err)
	}

	saveReq := sftpPathBookmarksRequest{
		History:   []string{"/var/log", "", ".", "/etc", "/var/log"},
		Favorites: []string{"/srv", "/opt", "/srv"},
	}
	w := runSftpBookmarkRequest(handler.SavePathBookmarks, 10, http.MethodPut, "/api/sftp/bookmarks/1", saveReq)
	if w.Code != http.StatusOK {
		t.Fatalf("save status = %d, body = %s", w.Code, w.Body.String())
	}

	w = runSftpBookmarkRequest(handler.GetPathBookmarks, 10, http.MethodGet, "/api/sftp/bookmarks/1", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("get status = %d, body = %s", w.Code, w.Body.String())
	}

	var resp struct {
		Success bool                      `json:"success"`
		Data    sftpPathBookmarksResponse `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if got, want := resp.Data.History, []string{"/var/log", "/etc"}; !equalStringSlices(got, want) {
		t.Fatalf("history = %#v, want %#v", got, want)
	}
	if got, want := resp.Data.Favorites, []string{"/srv", "/opt"}; !equalStringSlices(got, want) {
		t.Fatalf("favorites = %#v, want %#v", got, want)
	}
}

func TestSftpPathBookmarksRejectOtherUsersHost(t *testing.T) {
	db, handler := setupSftpBookmarksTest(t)
	if err := db.Create(&models.SSHHost{ID: 1, UserID: 10, Name: "host", Host: "127.0.0.1", Username: "root", AuthType: "password"}).Error; err != nil {
		t.Fatalf("create host: %v", err)
	}

	w := runSftpBookmarkRequest(handler.GetPathBookmarks, 99, http.MethodGet, "/api/sftp/bookmarks/1", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d, body = %s", w.Code, http.StatusNotFound, w.Body.String())
	}
}

func equalStringSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
