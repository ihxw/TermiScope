package main

import (
	"crypto/sha256"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/handlers"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/monitor"
	"github.com/ihxw/termiscope/internal/utils"
	"gopkg.in/natefinch/lumberjack.v2"

	_ "github.com/ihxw/termiscope/docs"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

// @title           TermiScope API
// @version         1.0
// @description     This is the API documentation for TermiScope Server.
// @termsOfService  http://swagger.io/terms/

// @contact.name    API Support
// @contact.url     http://www.swagger.io/support
// @contact.email   support@swagger.io

// @license.name    Apache 2.0
// @license.url     http://www.apache.org/licenses/LICENSE-2.0.html

// @host            localhost:8080
// @BasePath        /api
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization

// @name Authorization

func main() {
	var resetPwdUser string
	flag.StringVar(&resetPwdUser, "reset-pwd", "", "Reset password for specified username and exit")
	flag.Parse()

	// Load configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize database
	db, err := database.InitDB(cfg.Database.Path)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Run migrations (includes network monitor indexes)
	if err := database.RunMigrations(db); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}
	database.RunNetworkMonitorMaintenance(db, cfg.Security.EncryptionKey)

	// Handle CLI password reset BEFORE entering web server mode
	if resetPwdUser != "" {
		var user models.User
		if err := db.Where("username = ?", resetPwdUser).First(&user).Error; err != nil {
			log.Fatalf("Error: user '%s' not found", resetPwdUser)
		}
		newPwd := utils.GenerateRandomString(16)
		if err := user.SetPassword(newPwd); err != nil {
			log.Fatalf("Error generating password hash: %v", err)
		}
		if err := db.Save(&user).Error; err != nil {
			log.Fatalf("Error saving new password: %v", err)
		}
		log.Printf("\n========================================\n"+
			"PASSWORD RESET SUCCESSFUL\n"+
			"User: %s\n"+
			"New Password: %s\n"+
			"========================================\n"+
			"Please login with this password and change it immediately.\n", resetPwdUser, newPwd)
		os.Exit(0)
	}

	// Cleanup stale logs from previous run
	if err := database.CleanupStaleLogs(db); err != nil {
		log.Printf("Warning: Failed to cleanup stale logs: %v", err)
	}

	// Sync configuration from Database (System Settings)
	// This ensures DB values override file/defaults, and seeds defaults if missing.
	if err := config.SyncConfigFromDB(db, cfg); err != nil {
		log.Printf("Warning: Failed to sync config from DB: %v", err)
	}

	// Build agent hash cache only when agents/ changed (skipped on most restarts)
	if err := utils.EnsureAgentHashesFresh(); err != nil {
		log.Printf("Warning: Failed to ensure agent hashes: %v", err)
	}

	// Configure logging
	log.SetOutput(&lumberjack.Logger{
		Filename:   "logs/server.log",
		MaxSize:    10, // megabytes
		MaxBackups: 5,
		MaxAge:     30, // days
		Compress:   true,
	})

	// Initialize separate Error Logger
	utils.InitErrorLogger("logs/error.log")

	// Start Monitor Background Checker
	monitor.StartMonitorChecker(db, cfg.Security.EncryptionKey)

	// Create Gin router
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}
	router := gin.Default()

	// Set max upload size
	router.MaxMultipartMemory = cfg.Server.MaxUploadSize

	// Apply middlewares
	router.Use(middleware.Logger())         // Access logs
	router.Use(middleware.CustomRecovery()) // Custom panic recovery to error.log
	router.Use(middleware.CORS(cfg.Server.AllowedOrigins, cfg.Server.Mode == "debug"))

	// Global Middlewares
	router.Use(middleware.SecurityMiddleware())

	// Auth rate limiter (10 attempts per minute per IP)
	loginRateLimiter := middleware.NewRateLimiter(10, 1*time.Minute)
	refreshRateLimiter := middleware.NewRateLimiter(30, 1*time.Minute)

	// Agent rate limiter (500 requests per minute per IP — generous for multi-agent NAT setups)
	agentRateLimiter := middleware.NewRateLimiter(500, 1*time.Minute)
	agentIdentityRateLimiter := middleware.NewRateLimiter(120, 1*time.Minute)
	agentRateLimitKey := func(c *gin.Context) string {
		auth := c.GetHeader("Authorization")
		if strings.HasPrefix(auth, "Bearer ") {
			secret := strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
			if secret != "" {
				sum := sha256.Sum256([]byte(secret))
				return "agent:" + fmt.Sprintf("%x", sum[:])
			}
		}
		return "ip:" + c.ClientIP()
	}

	// Public routes
	authHandler := handlers.NewAuthHandler(db, cfg)
	handlers.LoginRateLimiter = loginRateLimiter // Set global reference for hot-reloading
	router.POST("/api/auth/login", loginRateLimiter.RateLimitMiddleware(), authHandler.Login)
	router.POST("/api/auth/verify-2fa-login", loginRateLimiter.RateLimitMiddleware(), authHandler.Verify2FALogin)
	router.POST("/api/auth/forgot-password", loginRateLimiter.RateLimitMiddleware(), authHandler.ForgotPassword)
	router.POST("/api/auth/reset-password", loginRateLimiter.RateLimitMiddleware(), authHandler.ResetPassword)
	router.POST("/api/auth/logout", authHandler.Logout)
	router.POST("/api/auth/refresh", refreshRateLimiter.RateLimitMiddleware(), authHandler.RefreshToken)
	router.GET("/api/system/info", authHandler.GetSystemInfo)
	router.GET("/api/auth/check-init", authHandler.CheckInit)
	router.POST("/api/auth/initialize", loginRateLimiter.RateLimitMiddleware(), authHandler.Initialize)

	// WebSocket SSH route (authenticated via one-time ticket in handler)
	sshWSHandler := handlers.NewSSHWebSocketHandler(db, cfg)
	router.GET("/api/ws/ssh/:hostId", sshWSHandler.HandleWebSocket)

	// WebSocket Monitor stream (authenticated via one-time ticket in handler)
	// Moved out of protected group: WebSocket cannot set Authorization headers cross-origin
	monitorHandler := handlers.NewMonitorHandler(db, cfg)
	router.GET("/api/monitor/stream", monitorHandler.Stream)

	// Monitor routes
	router.POST("/api/monitor/pulse", agentIdentityRateLimiter.RateLimitMiddlewareByKey(agentRateLimitKey), monitorHandler.Pulse)
	router.POST("/api/monitor/agent-event", agentIdentityRateLimiter.RateLimitMiddlewareByKey(agentRateLimitKey), monitorHandler.AgentEvent)
	router.GET("/api/monitor/agent-commands", agentIdentityRateLimiter.RateLimitMiddlewareByKey(agentRateLimitKey), monitorHandler.GetAgentCommands)
	router.GET("/api/monitor/install", monitorHandler.GetInstallScript)
	router.GET("/api/monitor/uninstall", monitorHandler.GetUninstallScript)
	router.POST("/api/monitor/uninstall/callback", agentRateLimiter.RateLimitMiddleware(), monitorHandler.UninstallCallback)
	router.GET("/api/monitor/agent-manifest", monitorHandler.GetAgentManifest)
	router.GET("/api/monitor/agent/:filename", monitorHandler.DownloadAgent)

	// Network Monitor Agent Routes
	netMonitorHandler := handlers.NewNetworkMonitorHandler(db)
	router.GET("/api/monitor/network/tasks", agentIdentityRateLimiter.RateLimitMiddlewareByKey(agentRateLimitKey), netMonitorHandler.GetNetworkTasks)
	router.POST("/api/monitor/network/report", agentIdentityRateLimiter.RateLimitMiddlewareByKey(agentRateLimitKey), netMonitorHandler.ReportNetworkResults)

	systemHandler := handlers.NewSystemHandler(db, cfg, config.Version)

	// Admin backup download: JWT/cookie or one-time ?token= (browser window.location)
	router.GET("/api/system/backup/download",
		middleware.AdminOrTicketMiddleware(cfg.Security.JWTSecret, db),
		systemHandler.DownloadBackup,
	)

	// Protected routes
	protected := router.Group("/api")
	protected.Use(middleware.AuthMiddleware(cfg.Security.JWTSecret, db))
	{
		// Auth routes
		protected.GET("/auth/me", authHandler.GetCurrentUser)
		protected.GET("/auth/token-info", authHandler.GetTokenInfo) // Diagnostic endpoint
		protected.POST("/auth/ws-ticket", authHandler.GetWSTicket)
		protected.POST("/auth/change-password", authHandler.ChangePassword)
		protected.GET("/auth/login-history", authHandler.GetLoginHistory)
		protected.POST("/auth/sessions/revoke", authHandler.RevokeSession)

		// SSH host routes
		sshHostHandler := handlers.NewSSHHostHandler(db, cfg)
		protected.GET("/ssh-hosts", sshHostHandler.List)
		protected.POST("/ssh-hosts", sshHostHandler.Create)
		protected.PUT("/ssh-hosts/:id", sshHostHandler.Update)
		protected.DELETE("/ssh-hosts/:id", sshHostHandler.Delete)
		protected.GET("/ssh-hosts/:id", sshHostHandler.Get)
		protected.POST("/ssh-hosts/:id/test", sshHostHandler.TestConnection)
		protected.PUT("/ssh-hosts/:id/fingerprint", sshHostHandler.UpdateFingerprint)
		protected.PUT("/ssh-hosts/reorder", sshHostHandler.Reorder)
		protected.DELETE("/ssh-hosts/:id/permanent", sshHostHandler.PermanentDelete)

		// Monitor Management (stream is in public routes above)
		protected.POST("/ssh-hosts/:id/monitor/deploy", monitorHandler.Deploy)
		protected.POST("/ssh-hosts/:id/monitor/update", monitorHandler.TriggerAgentUpdate)
		protected.POST("/ssh-hosts/:id/monitor/stop", monitorHandler.Stop)
		protected.POST("/ssh-hosts/monitor/batch-deploy", monitorHandler.BatchDeploy)
		protected.POST("/ssh-hosts/monitor/batch-stop", monitorHandler.BatchStop)
		protected.GET("/ssh-hosts/:id/monitor/logs", monitorHandler.GetStatusLogs)
		protected.GET("/ssh-hosts/:id/monitor/traffic-history", monitorHandler.GetHostTrafficHistory)
		protected.GET("/monitor/traffic-reset-logs", monitorHandler.GetTrafficResetLogs)
		protected.GET("/monitor/traffic-reset-debug/:id", monitorHandler.GetTrafficResetDebug)
		protected.POST("/monitor/traffic-reset-force/:id", monitorHandler.ForceTrafficReset)

		// Network Monitor Management (User)
		protected.POST("/monitor/network/tasks", netMonitorHandler.CreateTask)
		protected.PUT("/monitor/network/tasks/:id", netMonitorHandler.UpdateTask)
		protected.DELETE("/monitor/network/tasks/:id", netMonitorHandler.DeleteTask)
		protected.GET("/ssh-hosts/:id/network/tasks", netMonitorHandler.GetHostTasks)
		protected.GET("/ssh-hosts/:id/network/latency-stats", netMonitorHandler.GetHostLatencyStats)
		protected.GET("/monitor/network/stats/:taskId", netMonitorHandler.GetTaskStats)

		// Network Monitor Templates (System Settings)
		networkGroup := protected.Group("/monitor/network")
		networkGroup.GET("/templates", netMonitorHandler.GetTemplates)
		networkGroup.POST("/templates", netMonitorHandler.CreateTemplate)
		networkGroup.PUT("/templates/:id", netMonitorHandler.UpdateTemplate)
		networkGroup.DELETE("/templates/:id", netMonitorHandler.DeleteTemplate)
		networkGroup.POST("/apply-template", netMonitorHandler.BatchApplyTemplate)
		networkGroup.GET("/templates/:id/assignments", netMonitorHandler.GetTemplateAssignments)

		// SFTP routes
		sftpHandler := handlers.NewSftpHandler(db, cfg)
		protected.GET("/sftp/list/:hostId", sftpHandler.List)
		protected.GET("/sftp/bookmarks/:hostId", sftpHandler.GetPathBookmarks)
		protected.PUT("/sftp/bookmarks/:hostId", sftpHandler.SavePathBookmarks)
		protected.GET("/sftp/download/:hostId", sftpHandler.Download)
		protected.POST("/sftp/upload/:hostId", sftpHandler.Upload)
		protected.GET("/sftp/upload-progress/:uploadId", sftpHandler.GetUploadProgress)
		protected.DELETE("/sftp/delete/:hostId", sftpHandler.Delete)
		protected.POST("/sftp/rename/:hostId", sftpHandler.Rename)
		protected.POST("/sftp/paste/:hostId", sftpHandler.Paste)
		protected.POST("/sftp/mkdir/:hostId", sftpHandler.Mkdir)
		protected.POST("/sftp/create/:hostId", sftpHandler.CreateFile)
		protected.GET("/sftp/size/:hostId", sftpHandler.GetDirSize)
		protected.POST("/sftp/transfer", sftpHandler.Transfer)

		// Connection log routes
		logHandler := handlers.NewConnectionLogHandler(db)
		protected.GET("/connection-logs", logHandler.List)

		// Command template routes
		cmdHandler := handlers.NewCommandTemplateHandler(db)
		protected.GET("/command-templates", cmdHandler.List)
		protected.POST("/command-templates", cmdHandler.Create)
		protected.PUT("/command-templates/:id", cmdHandler.Update)
		protected.DELETE("/command-templates/:id", cmdHandler.Delete)

		// Recording routes
		recHandler := handlers.NewRecordingHandler(db)
		protected.GET("/recordings", recHandler.List)
		protected.GET("/recordings/:id/stream", recHandler.GetStream)
		protected.DELETE("/recordings/:id", recHandler.Delete)

		// 2FA routes
		twoFAHandler := handlers.NewTwoFactorHandler(db, cfg.Security.EncryptionKey)
		protected.POST("/auth/2fa/setup", twoFAHandler.Setup2FA)
		protected.POST("/auth/2fa/verify-setup", twoFAHandler.VerifySetup2FA)
		protected.POST("/auth/2fa/disable", twoFAHandler.Disable2FA)
		protected.POST("/auth/2fa/verify", twoFAHandler.Verify2FA)
		protected.POST("/auth/2fa/backup-codes", twoFAHandler.RegenerateBackupCodes)

		// Admin routes
		adminGroup := protected.Group("")
		adminGroup.Use(middleware.AdminMiddleware())
		{
			// User management
			userHandler := handlers.NewUserHandler(db)
			users := adminGroup.Group("/users")
			{
				users.GET("", userHandler.GetUsers)
				users.POST("", userHandler.CreateUser)
				users.PUT("/:id", userHandler.UpdateUser)
				users.DELETE("/:id", userHandler.DeleteUser)
			}

			// System management
			system := adminGroup.Group("/system")
			{
				system.POST("/backup", systemHandler.Backup)
				system.POST("/restore", systemHandler.Restore)
				system.GET("/settings", systemHandler.GetSettings)
				system.PUT("/settings", systemHandler.UpdateSettings)
				system.POST("/settings/test-email", systemHandler.TestEmail)
				system.POST("/settings/test-telegram", systemHandler.TestTelegram)
				system.POST("/check-update", systemHandler.CheckUpdate)
				system.POST("/upgrade", systemHandler.PerformUpdate)
				system.GET("/update-status", systemHandler.GetUpdateStatus)
				system.GET("/db-stats", systemHandler.GetDatabaseStats)
				system.POST("/db-maintenance/prune", systemHandler.PruneNetworkMonitorData)
			}

			adminGroup.GET("/monitor/orphan-agents", monitorHandler.ListOrphanAgents)
			adminGroup.GET("/monitor/orphan-agents/:id/cleanup-script", monitorHandler.GetOrphanCleanupScript)
			adminGroup.DELETE("/monitor/orphan-agents/:id", monitorHandler.DismissOrphanAgent)
		}

		// System routes (Protected but not Admin-only)
		protected.GET("/system/agent-version", systemHandler.GetAgentVersion)
	}

	// Serve static files (embedded frontend)
	// In development with Vite, this may be ignored as you use port 5173
	// In production or standalone mode, this serves the built Vue app
	router.Static("/assets", "./web/dist/assets")
	router.StaticFile("/favicon.ico", "./web/dist/favicon.ico") // Keep for legacy if file added later
	router.StaticFile("/favicon.png", "./web/dist/favicon.png")
	router.StaticFile("/logo.png", "./web/dist/logo.png")
	router.StaticFile("/", "./web/dist/index.html")

	// Swagger UI (Protected, only enabled in non-release mode for security)
	if cfg.Server.Mode != "release" {
		swaggerGroup := router.Group("/swagger")
		swaggerGroup.Use(middleware.AuthMiddleware(cfg.Security.JWTSecret, db))
		swaggerGroup.GET("/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
	}

	router.NoRoute(func(c *gin.Context) {
		// If the request is for an API route, return 404
		if strings.HasPrefix(c.Request.URL.Path, "/api") {
			c.JSON(http.StatusNotFound, gin.H{"error": "API route not found"})
			return
		}
		// Otherwise serve the index.html for SPA routing
		c.File("./web/dist/index.html")
	})

	// Start Login History Auto-Cleanup (retain 90 days, run once then daily)
	go func() {
		cleanupLoginHistory := func() {
			cutoff := time.Now().AddDate(0, 0, -90)
			if result := db.Where("login_at < ?", cutoff).Delete(&models.LoginHistory{}); result.Error != nil {
				log.Printf("Login history cleanup failed: %v", result.Error)
			} else if result.RowsAffected > 0 {
				log.Printf("Login history cleanup: removed %d records older than 90 days", result.RowsAffected)
			}
		}
		cleanupLoginHistory()
		ticker := time.NewTicker(24 * time.Hour)
		for range ticker.C {
			cleanupLoginHistory()
		}
	}()

	// Start server
	addr := fmt.Sprintf(":%d", cfg.Server.Port)
	localIP := getLocalIP()
	log.Printf("Starting TermiScope server on %s (http://%s:%d)", addr, localIP, cfg.Server.Port)
	if err := router.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// getLocalIP returns the non-loopback local IP of the host
func getLocalIP() string {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "127.0.0.1"
	}
	defer conn.Close()
	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP.String()
}
