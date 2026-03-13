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
		go SendEmail(configMap, configMap["smtp_to"], subject, finalMsg)
	}

	if strings.Contains(channels, "telegram") {
		go SendTelegram(configMap, finalMsg)
	}
}

// SendEmail sends an email using the provided configuration
func SendEmail(config map[string]string, to, subject, body string) error {
	server := config["smtp_server"]
	port := config["smtp_port"]
	user := config["smtp_user"]
	password := config["smtp_password"]
	from := config["smtp_from"]
	// to argument overrides config["smtp_to"]
	skipVerify := config["smtp_tls_skip_verify"] == "true"

	if server == "" || port == "" || from == "" || to == "" {
		return fmt.Errorf("missing configuration")
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
		return fmt.Errorf("SMTP Connection failed: %v", err)
	}
	defer conn.Close()

	// Client
	c, err := smtp.NewClient(conn, server)
	if err != nil {
		return fmt.Errorf("failed to create SMTP client: %v", err)
	}
	defer c.Quit()

	// Hello
	if err = c.Hello("localhost"); err != nil {
		return fmt.Errorf("SMTP Hello failed: %v", err)
	}

	// StartTLS if needed (port 587 or 25 usually)
	if port != "465" {
		if ok, _ := c.Extension("STARTTLS"); ok {
			if err = c.StartTLS(tlsConfig); err != nil {
				return fmt.Errorf("STARTTLS failed: %v", err)
			}
		}
	}

	// Auth
	if user != "" && password != "" {
		auth := smtp.PlainAuth("", user, password, server)
		if err = c.Auth(auth); err != nil {
			return fmt.Errorf("SMTP Auth failed: %v", err)
		}
	}

	// Send
	if err = c.Mail(from); err != nil {
		return fmt.Errorf("SMTP Mail cmd failed: %v", err)
	}
	if err = c.Rcpt(to); err != nil {
		return fmt.Errorf("SMTP Rcpt cmd failed: %v", err)
	}

	w, err := c.Data()
	if err != nil {
		return fmt.Errorf("SMTP Data cmd failed: %v", err)
	}

	msg := []byte("To: " + to + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/plain; charset=UTF-8\r\n" +
		"\r\n" +
		body + "\r\n")

	if _, err = w.Write(msg); err != nil {
		return fmt.Errorf("SMTP Write failed: %v", err)
	}
	if err = w.Close(); err != nil {
		return fmt.Errorf("SMTP Close failed: %v", err)
	}

	log.Printf("Notification: Email sent to %s", to)
	return nil
}

// SendTelegram sends a telegram message using the provided configuration
func SendTelegram(config map[string]string, message string) error {
	token := config["telegram_bot_token"]
	chatID := config["telegram_chat_id"]

	if token == "" || chatID == "" {
		return fmt.Errorf("missing token or chat_id")
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", token)

	reqBody, _ := json.Marshal(map[string]string{
		"chat_id":    chatID,
		"text":       message,
		"parse_mode": "Markdown",
	})

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(reqBody))
	if err != nil {
		return fmt.Errorf("failed to send telegram: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Telegram API error: %s", resp.Status)
	}

	log.Printf("Notification: Telegram message sent")
	return nil
}
