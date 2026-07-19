package utils

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
	"time"
)

type ScopedTicketData struct {
	UserID   uint
	Username string
	Role     string
	Scope    string
	Expires  time.Time
}

var scopedTickets = struct {
	sync.Mutex
	items map[string]ScopedTicketData
}{items: make(map[string]ScopedTicketData)}

const maxScopedTickets = 1000
const maxScopedTicketsPerUser = 50

func GenerateScopedTicket(userID uint, username, role, scope string, ttl time.Duration) string {
	if scope == "" || ttl <= 0 {
		return ""
	}
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	ticketID := hex.EncodeToString(b)

	scopedTickets.Lock()
	defer scopedTickets.Unlock()
	now := time.Now()
	for id, ticket := range scopedTickets.items {
		if now.After(ticket.Expires) {
			delete(scopedTickets.items, id)
		}
	}
	if len(scopedTickets.items) >= maxScopedTickets {
		return ""
	}
	userCount := 0
	for _, ticket := range scopedTickets.items {
		if ticket.UserID == userID {
			userCount++
		}
	}
	if userCount >= maxScopedTicketsPerUser {
		return ""
	}
	scopedTickets.items[ticketID] = ScopedTicketData{
		UserID: userID, Username: username, Role: role, Scope: scope, Expires: now.Add(ttl),
	}
	return ticketID
}

// ValidateScopedTicket validates a resource-bound ticket without consuming it.
// Download managers may issue multiple Range requests during the short ticket lifetime.
func ValidateScopedTicket(ticketID, scope string) (ScopedTicketData, bool) {
	if ticketID == "" || scope == "" {
		return ScopedTicketData{}, false
	}
	scopedTickets.Lock()
	defer scopedTickets.Unlock()
	ticket, ok := scopedTickets.items[ticketID]
	if !ok || time.Now().After(ticket.Expires) || ticket.Scope != scope {
		if ok && time.Now().After(ticket.Expires) {
			delete(scopedTickets.items, ticketID)
		}
		return ScopedTicketData{}, false
	}
	return ticket, true
}
