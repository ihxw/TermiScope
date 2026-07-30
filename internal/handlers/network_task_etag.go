package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"

	"github.com/ihxw/termiscope/internal/models"
)

func networkTasksETag(hostID uint, tasks []models.NetworkMonitorTask) string {
	h := sha256.New()
	_, _ = fmt.Fprintf(h, "host:%d:n:%d", hostID, len(tasks))
	for _, t := range tasks {
		_, _ = fmt.Fprintf(h, ";%d:%d:%s:%s:%d:%d",
			t.ID, t.UpdatedAt.UnixNano(), t.Type, t.Target, t.Port, t.Frequency)
	}
	return `"` + hex.EncodeToString(h.Sum(nil)[:16]) + `"`
}
