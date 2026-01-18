package utils

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/smtp"
	"strings"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

const DefaultNotificationTemplate = `{{emoji}}{{emoji}}{{emoji}}
Event: {{event}}
Clients: {{client}}
Message: {{message}}
Time: {{time}}`

// SendNotification routes the notification to enabled channels
func SendNotification(db *gorm.DB, host models.SSHHost, subject, message string) {
	channels := strings.ToLower(host.NotifyChannels)

	// Determine Emoji based on subject content (Hack, better to pass event type)
	emoji := "ℹ️"
	if strings.Contains(strings.ToLower(subject), "offline") {
		emoji = "🔴"
	} else if strings.Contains(strings.ToLower(subject), "online") {
		emoji = "🟢"
	} else if strings.Contains(strings.ToLower(subject), "traffic") {
		emoji = "⚠️"
	}

	// Load System Configs
	var configs []models.SystemConfig
	if err := db.Find(&configs).Error; err != nil {
		log.Printf("Notification: Failed to load system config: %v", err)
		return
	}

	configMap := make(map[string]string)
	for _, c := range configs {
		configMap[c.ConfigKey] = c.ConfigValue
	}

	// Prepare Template
	tmpl := configMap["notification_template"]
	if tmpl == "" {
		tmpl = DefaultNotificationTemplate
	}

	// Replace Variables
	finalMsg := strings.ReplaceAll(tmpl, "{{emoji}}", emoji)
	finalMsg = strings.ReplaceAll(finalMsg, "{{event}}", subject)
	finalMsg = strings.ReplaceAll(finalMsg, "{{client}}", host.Name)
	finalMsg = strings.ReplaceAll(finalMsg, "{{message}}", message)
	finalMsg = strings.ReplaceAll(finalMsg, "{{time}}", time.Now().Format("2006-01-02 15:04:05"))

	if strings.Contains(channels, "email") {
		go sendEmail(configMap, subject, finalMsg)
	}

	if strings.Contains(channels, "telegram") {
		go sendTelegram(configMap, finalMsg)
	}
}

func sendEmail(config map[string]string, subject, body string) {
	server := config["smtp_server"]
	port := config["smtp_port"]
	user := config["smtp_user"]
	password := config["smtp_password"]
	from := config["smtp_from"]
	to := config["smtp_to"]
	skipVerify := config["smtp_tls_skip_verify"] == "true"

	if server == "" || port == "" || from == "" || to == "" {
		log.Println("Notification: Email skipped, missing configuration")
		return
	}

	addr := net.JoinHostPort(server, port)

	// TLS Config
	tlsConfig := &tls.Config{
		InsecureSkipVerify: skipVerify,
		ServerName:         server,
	}

	// Log warning if TLS verification is disabled
	if skipVerify {
		log.Println("WARNING: SMTP TLS certificate verification is disabled. This is insecure!")
	}

	var conn net.Conn
	var err error

	// Connect
	if port == "465" {
		// Implicit TLS (SMTPS)
		conn, err = tls.Dial("tcp", addr, tlsConfig)
	} else {
		// StartTLS or Plain
		conn, err = net.DialTimeout("tcp", addr, 10*time.Second)
	}

	if err != nil {
		log.Printf("Notification: SMTP Connection failed: %v", err)
		return
	}
	defer conn.Close()

	// Client
	c, err := smtp.NewClient(conn, server)
	if err != nil {
		log.Printf("Notification: Failed to create SMTP client: %v", err)
		return
	}
	defer c.Quit()

	// Hello
	if err = c.Hello("localhost"); err != nil {
		log.Printf("Notification: SMTP Hello failed: %v", err)
		return
	}

	// StartTLS if needed (port 587 or 25 usually)
	if port != "465" {
		if ok, _ := c.Extension("STARTTLS"); ok {
			if err = c.StartTLS(tlsConfig); err != nil {
				log.Printf("Notification: STARTTLS failed: %v", err)
				return
			}
		}
	}

	// Auth
	if user != "" && password != "" {
		auth := smtp.PlainAuth("", user, password, server)
		if err = c.Auth(auth); err != nil {
			log.Printf("Notification: SMTP Auth failed: %v", err)
			return
		}
	}

	// Send
	if err = c.Mail(from); err != nil {
		log.Printf("Notification: SMTP Mail cmd failed: %v", err)
		return
	}
	if err = c.Rcpt(to); err != nil {
		log.Printf("Notification: SMTP Rcpt cmd failed: %v", err)
		return
	}

	w, err := c.Data()
	if err != nil {
		log.Printf("Notification: SMTP Data cmd failed: %v", err)
		return
	}

	msg := []byte("To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/plain; charset=UTF-8\r\n" +
		"\r\n" +
		body + "\r\n")

	if _, err = w.Write(msg); err != nil {
		log.Printf("Notification: SMTP Write failed: %v", err)
		return
	}
	if err = w.Close(); err != nil {
		log.Printf("Notification: SMTP Close failed: %v", err)
		return
	}

	log.Printf("Notification: Email sent to %s", to)
}

func sendTelegram(config map[string]string, message string) {
	token := config["telegram_bot_token"]
	chatID := config["telegram_chat_id"]

	if token == "" || chatID == "" {
		log.Println("Notification: Telegram skipped, missing token or chat_id")
		return
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", token)

	reqBody, _ := json.Marshal(map[string]string{
		"chat_id":    chatID,
		"text":       message,
		"parse_mode": "Markdown",
	})

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(reqBody))
	if err != nil {
		log.Printf("Notification: Failed to send telegram: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("Notification: Telegram API error: %s", resp.Status)
	} else {
		log.Printf("Notification: Telegram message sent")
	}
}
