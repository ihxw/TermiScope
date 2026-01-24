package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/handlers"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/monitor"
	"github.com/ihxw/termiscope/internal/utils"
	"gopkg.in/natefinch/lumberjack.v2"
)

func main() {
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

	// Run migrations
	if err := database.RunMigrations(db); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
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
	monitor.StartMonitorChecker(db)

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
	router.Use(middleware.CORS(cfg.Server.AllowedOrigins))

	// Global Middlewares
	router.Use(middleware.SecurityMiddleware())

	// Auth rate limiter (20 attempts per minute per IP)
	loginRateLimiter := middleware.NewRateLimiter(20, 1*time.Minute)

	// Public routes
	authHandler := handlers.NewAuthHandler(db, cfg)
	handlers.LoginRateLimiter = loginRateLimiter // Set global reference for hot-reloading
	router.POST("/api/auth/login", loginRateLimiter.RateLimitMiddleware(), authHandler.Login)
	router.POST("/api/auth/verify-2fa-login", authHandler.Verify2FALogin)
	router.POST("/api/auth/logout", authHandler.Logout)
	router.POST("/api/auth/refresh", authHandler.RefreshToken)
	router.GET("/api/system/info", authHandler.GetSystemInfo)

	// WebSocket SSH route (authenticated via one-time ticket in handler)
	sshWSHandler := handlers.NewSSHWebSocketHandler(db, cfg)
	router.GET("/api/ws/ssh/:hostId", sshWSHandler.HandleWebSocket)

	// Monitor routes
	monitorHandler := handlers.NewMonitorHandler(db, cfg)
	router.POST("/api/monitor/pulse", monitorHandler.Pulse)                          // Agent reports here using Secret Header
	router.GET("/api/monitor/install", monitorHandler.GetInstallScript)              // Public install script (verified by host secret)
	router.GET("/api/monitor/uninstall", monitorHandler.GetUninstallScript)          // Public uninstall script
	router.POST("/api/monitor/uninstall/callback", monitorHandler.UninstallCallback) // Callback from uninstall script
	router.GET("/api/monitor/agent/:filename", monitorHandler.DownloadAgent)         // Public agent download (verified by host secret)

	// Network Monitor Agent Routes
	netMonitorHandler := handlers.NewNetworkMonitorHandler(db)
	router.GET("/api/monitor/network/tasks", netMonitorHandler.GetNetworkTasks)
	router.POST("/api/monitor/network/report", netMonitorHandler.ReportNetworkResults)

	// Protected routes
	protected := router.Group("/api")
	protected.Use(middleware.AuthMiddleware(cfg.Security.JWTSecret))
	{
		// Auth routes
		protected.GET("/auth/me", authHandler.GetCurrentUser)
		protected.GET("/auth/token-info", authHandler.GetTokenInfo) // Diagnostic endpoint
		protected.POST("/auth/ws-ticket", authHandler.GetWSTicket)
		protected.POST("/auth/change-password", authHandler.ChangePassword)

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

		// Monitor Management
		protected.GET("/monitor/stream", monitorHandler.Stream)
		protected.POST("/ssh-hosts/:id/monitor/deploy", monitorHandler.Deploy)
		protected.POST("/ssh-hosts/:id/monitor/stop", monitorHandler.Stop)
		protected.POST("/ssh-hosts/monitor/batch-deploy", monitorHandler.BatchDeploy)
		protected.POST("/ssh-hosts/monitor/batch-stop", monitorHandler.BatchStop)
		protected.GET("/ssh-hosts/:id/monitor/logs", monitorHandler.GetStatusLogs)

		// Network Monitor Management (User)
		protected.POST("/monitor/network/tasks", netMonitorHandler.CreateTask)
		protected.PUT("/monitor/network/tasks/:id", netMonitorHandler.UpdateTask)
		protected.DELETE("/monitor/network/tasks/:id", netMonitorHandler.DeleteTask)
		protected.GET("/ssh-hosts/:id/network/tasks", netMonitorHandler.GetHostTasks)
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
		protected.GET("/sftp/download/:hostId", sftpHandler.Download)
		protected.POST("/sftp/upload/:hostId", sftpHandler.Upload)
		protected.DELETE("/sftp/delete/:hostId", sftpHandler.Delete)
		protected.POST("/sftp/rename/:hostId", sftpHandler.Rename)
		protected.POST("/sftp/paste/:hostId", sftpHandler.Paste)
		protected.POST("/sftp/mkdir/:hostId", sftpHandler.Mkdir)
		protected.POST("/sftp/create/:hostId", sftpHandler.CreateFile)

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
			systemHandler := handlers.NewSystemHandler(db, cfg)
			system := adminGroup.Group("/system")
			{
				system.GET("/backup", systemHandler.Backup)
				system.POST("/restore", systemHandler.Restore)
				system.GET("/settings", systemHandler.GetSettings)
				system.PUT("/settings", systemHandler.UpdateSettings)
			}
		}

		// System routes (Protected but not Admin-only)
		systemHandler := handlers.NewSystemHandler(db, cfg)
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

	router.NoRoute(func(c *gin.Context) {
		// If the request is for an API route, return 404
		if strings.HasPrefix(c.Request.URL.Path, "/api") {
			c.JSON(http.StatusNotFound, gin.H{"error": "API route not found"})
			return
		}
		// Otherwise serve the index.html for SPA routing
		c.File("./web/dist/index.html")
	})

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
