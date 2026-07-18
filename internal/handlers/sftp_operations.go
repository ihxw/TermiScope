package handlers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"path"
	"regexp"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/utils"
	"github.com/pkg/sftp"
)

const (
	defaultSFTPConcurrency       = 32
	defaultMaxSFTPOperations     = 16
	defaultMaxSFTPOperationsUser = 8
	hardMaxSFTPOperations        = 128
	maxUploadProgressEntries     = 1000
	maxUploadProgressPerUser     = 50
	uploadProgressTTL            = 5 * time.Minute
)

var errDestinationExists = errors.New("destination already exists")

type sftpOperationLimiter struct {
	mu        sync.Mutex
	active    int
	byUser    map[uint]int
	waiting   int
	waitUser  map[uint]int
	max       int
	maxByUser int
}

func newSFTPOperationLimiter(max, maxByUser int) *sftpOperationLimiter {
	if max <= 0 {
		max = defaultMaxSFTPOperations
	}
	if maxByUser <= 0 {
		maxByUser = defaultMaxSFTPOperationsUser
	}
	if max > hardMaxSFTPOperations {
		max = hardMaxSFTPOperations
	}
	if maxByUser > max {
		maxByUser = max
	}
	return &sftpOperationLimiter{
		byUser: make(map[uint]int), waitUser: make(map[uint]int), max: max, maxByUser: maxByUser,
	}
}

func (l *sftpOperationLimiter) acquire(ctx context.Context, userID uint) (func(), bool) {
	if release, ok := l.tryAcquire(userID); ok {
		return release, true
	}
	l.mu.Lock()
	if l.waiting >= l.max*2 || l.waitUser[userID] >= l.maxByUser*2 {
		l.mu.Unlock()
		return nil, false
	}
	l.waiting++
	l.waitUser[userID]++
	l.mu.Unlock()

	removeWaiter := func() {
		l.mu.Lock()
		defer l.mu.Unlock()
		l.waiting--
		l.waitUser[userID]--
		if l.waitUser[userID] == 0 {
			delete(l.waitUser, userID)
		}
	}
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			removeWaiter()
			return nil, false
		case <-ticker.C:
			if release, ok := l.tryAcquire(userID); ok {
				removeWaiter()
				return release, true
			}
		}
	}
}

func (l *sftpOperationLimiter) tryAcquire(userID uint) (func(), bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.active >= l.max || l.byUser[userID] >= l.maxByUser {
		return nil, false
	}
	l.active++
	l.byUser[userID]++
	var once sync.Once
	return func() {
		once.Do(func() {
			l.mu.Lock()
			defer l.mu.Unlock()
			l.active--
			l.byUser[userID]--
			if l.byUser[userID] == 0 {
				delete(l.byUser, userID)
			}
		})
	}, true
}

func (h *SftpHandler) acquireOperation(c *gin.Context, userID uint) (func(), bool) {
	if h.operations == nil {
		h.operations = newSFTPOperationLimiter(0, 0)
	}
	release, ok := h.operations.tryAcquire(userID)
	if !ok {
		utils.ErrorResponse(c, http.StatusTooManyRequests, "too many active SFTP operations")
		return nil, false
	}
	return release, true
}

func (h *SftpHandler) waitForOperation(c *gin.Context, userID uint) (func(), bool) {
	if h.operations == nil {
		h.operations = newSFTPOperationLimiter(0, 0)
	}
	release, ok := h.operations.acquire(c.Request.Context(), userID)
	if !ok {
		utils.ErrorResponse(c, http.StatusTooManyRequests, "SFTP operation queue is full")
		return nil, false
	}
	return release, true
}

type uploadProgressEntry struct {
	userID  uint
	data    UploadProgressData
	expires time.Time
}

type uploadProgressStore struct {
	mu      sync.Mutex
	entries map[string]uploadProgressEntry
}

func newUploadProgressStore() *uploadProgressStore {
	return &uploadProgressStore{entries: make(map[string]uploadProgressEntry)}
}

func (s *uploadProgressStore) cleanupLocked(now time.Time) {
	for id, entry := range s.entries {
		if now.After(entry.expires) {
			delete(s.entries, id)
		}
	}
}

func (s *uploadProgressStore) create(userID uint, uploadID string, data UploadProgressData) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	s.cleanupLocked(now)
	if _, exists := s.entries[uploadID]; exists || len(s.entries) >= maxUploadProgressEntries {
		return false
	}
	userCount := 0
	for _, entry := range s.entries {
		if entry.userID == userID {
			userCount++
		}
	}
	if userCount >= maxUploadProgressPerUser {
		return false
	}
	s.entries[uploadID] = uploadProgressEntry{userID: userID, data: data, expires: now.Add(uploadProgressTTL)}
	time.AfterFunc(uploadProgressTTL, func() { s.delete(userID, uploadID) })
	return true
}

func (s *uploadProgressStore) update(userID uint, uploadID string, data UploadProgressData) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	entry, ok := s.entries[uploadID]
	if !ok || entry.userID != userID || time.Now().After(entry.expires) {
		return false
	}
	entry.data = data
	s.entries[uploadID] = entry
	return true
}

func (s *uploadProgressStore) get(userID uint, uploadID string) (UploadProgressData, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	s.cleanupLocked(now)
	entry, ok := s.entries[uploadID]
	if !ok || entry.userID != userID {
		return UploadProgressData{}, false
	}
	return entry.data, true
}

func (s *uploadProgressStore) delete(userID uint, uploadID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if entry, ok := s.entries[uploadID]; ok && entry.userID == userID {
		delete(s.entries, uploadID)
	}
}

var (
	uploadIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)
	uploadProgress  = newUploadProgressStore()
)

func remoteStagingPath(target string) string {
	dir := path.Dir(target)
	base := path.Base(target)
	return path.Join(dir, fmt.Sprintf(".%s.termiscope-%s.part", base, utils.GenerateRandomString(12)))
}

func resolveRemoteTargetPath(client *sftp.Client, target string) (string, error) {
	if resolved, err := resolveSftpPath(client, target); err == nil {
		return resolved, nil
	}
	parent, err := resolveSftpPath(client, path.Dir(target))
	if err != nil {
		return "", err
	}
	return joinRemotePath(parent, path.Base(target)), nil
}

func (h *SftpHandler) commitRemotePath(client *sftp.Client, staged, target string, overwrite bool) error {
	_, statErr := client.Lstat(target)
	targetExists := statErr == nil
	if statErr != nil && !isRemoteNotExistError(statErr) {
		return fmt.Errorf("stat destination: %w", statErr)
	}
	if targetExists && !overwrite {
		return errDestinationExists
	}

	if !targetExists {
		if err := client.Rename(staged, target); err != nil {
			return fmt.Errorf("commit destination: %w", err)
		}
		return nil
	}

	if err := client.PosixRename(staged, target); err == nil {
		return nil
	}

	backup := remoteStagingPath(target) + ".backup"
	if err := client.Rename(target, backup); err != nil {
		return fmt.Errorf("stage existing destination: %w", err)
	}
	if err := client.Rename(staged, target); err != nil {
		_ = client.Rename(backup, target)
		return fmt.Errorf("commit destination: %w", err)
	}
	if err := h.deleteRecursive(client, backup); err != nil && !isRemoteNotExistError(err) {
		// The requested target is already committed. A hidden backup is safer
		// than reporting the successful replacement as failed.
		return nil
	}
	return nil
}
