package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLoadAgentConfigAcceptsUTF8BOM(t *testing.T) {
	resetAgentConfigGlobals(t)
	path := filepath.Join(t.TempDir(), "agent.json")
	data := append([]byte{0xEF, 0xBB, 0xBF}, []byte(`{"server_url":"https://ts.example.com","secret":"secret-value","host_id":48,"interval":"15s","insecure":true}`)...)
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	if err := loadAgentConfig(path); err != nil {
		t.Fatalf("load config with BOM: %v", err)
	}

	if serverURL != "https://ts.example.com" {
		t.Fatalf("serverURL = %q", serverURL)
	}
	if secret != "secret-value" {
		t.Fatalf("secret = %q", secret)
	}
	if hostID != 48 {
		t.Fatalf("hostID = %d", hostID)
	}
	if metricsInterval != 15*time.Second {
		t.Fatalf("metricsInterval = %s", metricsInterval)
	}
	if !insecure {
		t.Fatal("insecure = false")
	}
}

func resetAgentConfigGlobals(t *testing.T) {
	t.Helper()
	oldServerURL := serverURL
	oldSecret := secret
	oldHostID := hostID
	oldInsecure := insecure
	oldMetricsInterval := metricsInterval
	t.Cleanup(func() {
		serverURL = oldServerURL
		secret = oldSecret
		hostID = oldHostID
		insecure = oldInsecure
		metricsInterval = oldMetricsInterval
	})
	serverURL = ""
	secret = ""
	hostID = 0
	insecure = false
	metricsInterval = defaultMetricsInterval
}
