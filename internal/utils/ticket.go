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

// GenerateTicket creates a short-lived one-time ticket
func GenerateTicket(userID uint, username, role string) string {
	b := make([]byte, 16)
	rand.Read(b)
	ticketID := hex.EncodeToString(b)

	mu.Lock()
	defer mu.Unlock()

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
