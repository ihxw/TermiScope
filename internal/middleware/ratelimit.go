package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

const maxTrackedIPs = 10000 // Cap on number of tracked IPs

// RateLimiter stores request counts and timestamps by IP
type RateLimiter struct {
	requests map[string][]time.Time
	mu       sync.Mutex
	limit    int
	window   time.Duration
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	rl := &RateLimiter{
		requests: make(map[string][]time.Time),
		limit:    limit,
		window:   window,
	}

	// Periodic cleanup of old entries
	go func() {
		for {
			time.Sleep(window)
			rl.cleanup()
		}
	}()

	return rl
}

func (rl *RateLimiter) allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	valid := rl.requests[key][:0]
	for _, t := range rl.requests[key] {
		if now.Sub(t) < rl.window {
			valid = append(valid, t)
		}
	}

	if len(valid) >= rl.limit {
		rl.requests[key] = valid
		return false
	}

	rl.requests[key] = append(valid, now)
	return true
}

func (rl *RateLimiter) cleanup() {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	for ip, times := range rl.requests {
		var valid []time.Time
		for _, t := range times {
			if now.Sub(t) < rl.window {
				valid = append(valid, t)
			}
		}
		if len(valid) == 0 {
			delete(rl.requests, ip)
		} else {
			rl.requests[ip] = valid
		}
	}

	// If still too many IPs after cleanup, evict oldest (by first timestamp)
	if len(rl.requests) > maxTrackedIPs {
		type ipEntry struct {
			ip string
			ts time.Time
		}
		oldest := make([]ipEntry, 0, len(rl.requests))
		for ip, times := range rl.requests {
			oldest = append(oldest, ipEntry{ip, times[0]})
		}
		// Sort by timestamp (oldest first)
		for i := 0; i < len(oldest); i++ {
			for j := i + 1; j < len(oldest); j++ {
				if oldest[j].ts.Before(oldest[i].ts) {
					oldest[i], oldest[j] = oldest[j], oldest[i]
				}
			}
		}
		// Delete oldest entries to get back under limit
		toDelete := len(rl.requests) - maxTrackedIPs
		for i := 0; i < toDelete; i++ {
			delete(rl.requests, oldest[i].ip)
		}
	}
}

// RateLimitMiddleware returns a Gin handler for rate limiting
func (rl *RateLimiter) RateLimitMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !rl.allow(c.ClientIP()) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error":   "too many attempts, please try again later",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// RateLimitMiddlewareByKey returns a Gin handler for custom-key rate limiting.
// If keyFn returns an empty key, it falls back to the client IP.
func (rl *RateLimiter) RateLimitMiddlewareByKey(keyFn func(*gin.Context) string) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := ""
		if keyFn != nil {
			key = keyFn(c)
		}
		if key == "" {
			key = c.ClientIP()
		}

		if !rl.allow(key) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"error":   "too many attempts, please try again later",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// SetLimit updates the rate limit at runtime
func (rl *RateLimiter) SetLimit(limit int) {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	rl.limit = limit
}
