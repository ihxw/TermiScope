package utils

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
	"time"
)

type TicketData struct {
	UserID   uint
	Username string
	Role     string
	Expires  time.Time
}

var (
	tickets = make(map[string]TicketData)
	mu      sync.Mutex
)

// maxTickets limits the total number of in-memory tickets to prevent DoS
const maxTickets = 1000

// GenerateTicket creates a short-lived one-time ticket
func GenerateTicket(userID uint, username, role string) string {
	b := make([]byte, 16)
	rand.Read(b)
	ticketID := hex.EncodeToString(b)

	mu.Lock()
	defer mu.Unlock()

	// Security: Enforce capacity limit
	if len(tickets) >= maxTickets {
		// Evict expired tickets first
		now := time.Now()
		for id, data := range tickets {
			if now.After(data.Expires) {
				delete(tickets, id)
			}
		}
		// If still over limit, reject
		if len(tickets) >= maxTickets {
			return ""
		}
	}

	// Security: Limit per-user active tickets (max 10)
	userCount := 0
	for _, data := range tickets {
		if data.UserID == userID {
			userCount++
		}
	}
	if userCount >= 10 {
		// Evict oldest ticket for this user
		var oldestID string
		var oldestTime time.Time
		for id, data := range tickets {
			if data.UserID == userID {
				if oldestID == "" || data.Expires.Before(oldestTime) {
					oldestID = id
					oldestTime = data.Expires
				}
			}
		}
		if oldestID != "" {
			delete(tickets, oldestID)
		}
	}

	tickets[ticketID] = TicketData{
		UserID:   userID,
		Username: username,
		Role:     role,
		Expires:  time.Now().Add(30 * time.Second),
	}

	return ticketID
}

// ValidateTicket checks if a ticket is valid and deletes it (one-time use)
func ValidateTicket(ticketID string) (TicketData, bool) {
	if ticketID == "" {
		return TicketData{}, false
	}

	mu.Lock()
	defer mu.Unlock()

	data, ok := tickets[ticketID]
	if !ok {
		return TicketData{}, false
	}

	// Remove after use (One-time)
	delete(tickets, ticketID)

	if time.Now().After(data.Expires) {
		return TicketData{}, false
	}

	return data, true
}

// CleanupTickets removes expired tickets
func CleanupTickets() {
	mu.Lock()
	defer mu.Unlock()

	now := time.Now()
	for id, data := range tickets {
		if now.After(data.Expires) {
			delete(tickets, id)
		}
	}
}

func init() {
	// Start a background cleaner
	go func() {
		for {
			time.Sleep(1 * time.Minute)
			CleanupTickets()
		}
	}()
}
