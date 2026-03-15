package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type agentCommand struct {
	ID      uint   `json:"id"`
	HostID  uint   `json:"host_id"`
	Command string `json:"command"`
}

// pollAgentCommands periodically polls server for commands and executes them.
func pollAgentCommands(client *http.Client, stopCh <-chan struct{}) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-stopCh:
			return
		case <-ticker.C:
			fetchAndHandleCommands(client)
		}
	}
}

func fetchAndHandleCommands(client *http.Client) {
	url := fmt.Sprintf("%s/api/monitor/agent-commands?host_id=%d", strings.TrimRight(serverURL, "/"), hostID)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return
	}
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		io.Copy(io.Discard, resp.Body)
		return
	}

	var payload struct {
		Commands []agentCommand `json:"commands"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return
	}

	for _, cmd := range payload.Commands {
		switch cmd.Command {
		case "update":
			// Attempt immediate self-update
			_ = attemptAgentSelfUpdate(client)
		}
	}
}
