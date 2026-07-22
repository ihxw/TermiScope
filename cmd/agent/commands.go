package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/ihxw/termiscope/internal/agenttransfer"
)

const (
	agentCommandLongPollWait   = 25 * time.Second
	agentCommandRequestTimeout = 35 * time.Second
	agentCommandRetryDelay     = time.Second
)

type agentCommand struct {
	ID      uint   `json:"id"`
	HostID  uint   `json:"host_id"`
	Command string `json:"command"`
	Payload string `json:"payload"`
}

// pollAgentCommands keeps one long-poll request open so server-issued commands
// can be delivered immediately without frequent empty requests.
func pollAgentCommands(client *http.Client, stopCh <-chan struct{}) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() {
		select {
		case <-stopCh:
			cancel()
		case <-ctx.Done():
		}
	}()

	commandClient := *client
	commandClient.Timeout = agentCommandRequestTimeout

	for {
		err := fetchAndHandleCommands(ctx, &commandClient, client)
		if ctx.Err() != nil {
			return
		}
		if err == nil {
			continue
		}
		logError("Failed to receive agent commands: %v", err)
		timer := time.NewTimer(agentCommandRetryDelay)
		select {
		case <-ctx.Done():
			if !timer.Stop() {
				<-timer.C
			}
			return
		case <-timer.C:
		}
	}
}

func fetchAndHandleCommands(ctx context.Context, commandClient, operationClient *http.Client) error {
	url := fmt.Sprintf("%s/api/monitor/agent-commands?host_id=%d&wait=%d", strings.TrimRight(serverURL, "/"), hostID, int(agentCommandLongPollWait/time.Second))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := commandClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		io.Copy(io.Discard, resp.Body)
		return fmt.Errorf("command endpoint returned HTTP %d", resp.StatusCode)
	}

	var payload struct {
		Commands []agentCommand `json:"commands"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return err
	}

	for _, cmd := range payload.Commands {
		switch cmd.Command {
		case "update":
			// Attempt immediate self-update
			_ = attemptAgentSelfUpdate(operationClient)
		case agenttransfer.CommandName:
			var transfer agenttransfer.Command
			if err := json.Unmarshal([]byte(cmd.Payload), &transfer); err != nil {
				continue
			}
			go executeAgentTransfer(operationClient, transfer)
		case agenttransfer.ConfigurePortCommandName:
			var config agenttransfer.ConfigurePortCommand
			if err := json.Unmarshal([]byte(cmd.Payload), &config); err != nil {
				continue
			}
			applyAgentTransferPort(operationClient, config.Port)
		}
	}
	return nil
}

func applyAgentTransferPort(client *http.Client, port int) {
	persisted, err := reconfigureAgentTransferServer(port)
	if err != nil {
		_ = sendAgentPortEvent(client, "transfer_port_error", err.Error(), port)
		return
	}
	if err := sendMetrics(client, collectMetrics(false)); err != nil {
		logError("Failed to report transfer port change: %v", err)
	}
	message := fmt.Sprintf("transfer port changed to %d", port)
	if !persisted {
		message += " (runtime only; agent has no config file)"
	}
	_ = sendAgentPortEvent(client, "transfer_port_updated", message, port)
}
