package handlers

import (
	"bufio"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

const (
	defaultServerLogLines = 300
	maxServerLogLines     = 2000
)

type serverLogFile struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Path  string `json:"path"`
}

var allowedServerLogs = map[string]serverLogFile{
	"server": {Key: "server", Label: "Server", Path: "logs/server.log"},
	"error":  {Key: "error", Label: "Error", Path: "logs/error.log"},
}

func (h *SystemHandler) GetServerLogs(c *gin.Context) {
	logType := strings.ToLower(strings.TrimSpace(c.DefaultQuery("type", "server")))
	logFile, ok := allowedServerLogs[logType]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported log type"})
		return
	}

	lines, _ := strconv.Atoi(c.DefaultQuery("lines", strconv.Itoa(defaultServerLogLines)))
	if lines <= 0 {
		lines = defaultServerLogLines
	}
	if lines > maxServerLogLines {
		lines = maxServerLogLines
	}

	content, truncated, err := tailLines(logFile.Path, lines)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			c.JSON(http.StatusOK, gin.H{
				"type":      logFile.Key,
				"label":     logFile.Label,
				"path":      filepath.ToSlash(logFile.Path),
				"lines":     []string{},
				"truncated": false,
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read log file"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"type":      logFile.Key,
		"label":     logFile.Label,
		"path":      filepath.ToSlash(logFile.Path),
		"lines":     content,
		"truncated": truncated,
	})
}

func tailLines(path string, maxLines int) ([]string, bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, false, err
	}
	defer f.Close()

	ring := make([]string, maxLines)
	count := 0
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		if maxLines > 0 {
			ring[count%maxLines] = scanner.Text()
		}
		count++
	}
	if err := scanner.Err(); err != nil && !errors.Is(err, io.EOF) {
		return nil, false, err
	}

	if count <= maxLines {
		return ring[:count], false, nil
	}

	out := make([]string, maxLines)
	start := count % maxLines
	copy(out, ring[start:])
	copy(out[maxLines-start:], ring[:start])
	return out, true, nil
}
