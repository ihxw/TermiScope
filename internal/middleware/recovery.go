package middleware

import (
	"net"
	"net/http"
	"os"
	"runtime/debug"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/utils"
)

// CustomRecovery returns a middleware that recovers from any panics and writes a 500 if there was one.
func CustomRecovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if err := recover(); err != nil {
				// Check for a broken connection, as it is not really a condition that warrants a panic stack trace.
				var brokenPipe bool
				if ne, ok := err.(*net.OpError); ok {
					if se, ok := ne.Err.(*os.SyscallError); ok {
						if strings.Contains(strings.ToLower(se.Error()), "broken pipe") || strings.Contains(strings.ToLower(se.Error()), "connection reset by peer") {
							brokenPipe = true
						}
					}
				}

				stack := string(debug.Stack())

				if brokenPipe {
					utils.LogError("Broken pipe: %v\n%s", err, stack)
					c.Error(err.(error)) // nolint: errcheck
					c.Abort()
					return
				}

				// Log the panic
				utils.LogError("PANIC RECOVERED: %v\nStack Trace:\n%s", err, stack)

				// Respond with 500
				c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
					"error": "Internal Server Error",
				})
			}
		}()
		c.Next()
	}
}
