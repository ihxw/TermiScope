package monitor

import (
	"encoding/json"
	"runtime/debug"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/ihxw/termiscope/internal/utils"
)

// InterfaceData holds per-interface metrics
type InterfaceData struct {
	Name string   `json:"name"`
	Rx   uint64   `json:"rx"`
	Tx   uint64   `json:"tx"`
	IPs  []string `json:"ips"`
	Mac  string   `json:"mac"`
	// Derived rates
	RxRate uint64 `json:"rx_rate"`
	TxRate uint64 `json:"tx_rate"`
}

// DiskData holds per-partition disk metrics
type DiskData struct {
	MountPoint string `json:"mount_point"`
	Used       uint64 `json:"used"`  // Bytes
	Total      uint64 `json:"total"` // Bytes
}

// MetricData represents the data packet sent by the agent
type MetricData struct {
	HostID       uint    `json:"host_id"`
	Timestamp    int64   `json:"timestamp"` // Unix Timestamp
	AgentVersion string  `json:"agent_version"`
	Uptime       uint64  `json:"uptime"` // Seconds
	CPU          float64 `json:"cpu"`    // Percentage
	CpuCount     int     `json:"cpu_count"`
	CpuModel     string  `json:"cpu_model"`
	CpuMhz       float64 `json:"cpu_mhz"`
	MemUsed      uint64  `json:"mem_used"`    // Bytes
	MemTotal     uint64  `json:"mem_total"`   // Bytes
	DiskUsed     uint64  `json:"disk_used"`   // Bytes
	DiskTotal    uint64  `json:"disk_total"`  // Bytes
	NetRx        uint64  `json:"net_rx"`      // Total Bytes In
	NetTx        uint64  `json:"net_tx"`      // Total Bytes Out
	NetRxRate    uint64  `json:"net_rx_rate"` // Bytes/sec (Total)
	NetTxRate    uint64  `json:"net_tx_rate"` // Bytes/sec (Total)
	NetMonthlyRx uint64  `json:"net_monthly_rx"`
	NetMonthlyTx uint64  `json:"net_monthly_tx"`
	// Config for Frontend Calculation
	NetTrafficLimit          uint64 `json:"net_traffic_limit"`
	NetTrafficUsedAdjustment uint64 `json:"net_traffic_used_adjustment"`
	NetTrafficCounterMode    string `json:"net_traffic_counter_mode"` // total, rx, tx

	Interfaces  []InterfaceData `json:"interfaces"` // Per Interface
	Disks       []DiskData      `json:"disks"`      // Per Partition (empty for old agents)
	OS          string          `json:"os"`
	Hostname    string          `json:"hostname"`
	LastUpdated int64           `json:"last_updated"`

	AgentUpdateStatus string `json:"agent_update_status"` // Inline update status for UI
}

// AgentEvent represents a status event from the agent
type AgentEvent struct {
	HostID  uint   `json:"host_id"`
	Event   string `json:"event"`
	Message string `json:"message"`
}

type wsClient struct {
	conn      *websocket.Conn
	isAdmin   bool
	allowed   map[uint]bool // nil = admin (all hosts)
}

type Hub struct {
	clients   map[*wsClient]bool
	clientsMu sync.RWMutex

	hosts   map[uint]*MetricData
	hostsMu sync.RWMutex

	updateChan     chan MetricData
	agentEventChan chan AgentEvent
}

var GlobalHub = NewHub()

func NewHub() *Hub {
	return &Hub{
		clients:        make(map[*wsClient]bool),
		hosts:          make(map[uint]*MetricData),
		updateChan:     make(chan MetricData, 100),
		agentEventChan: make(chan AgentEvent, 100),
	}
}

func (h *Hub) Run() {
	defer func() {
		if err := recover(); err != nil {
			utils.LogError("Monitor Hub Panic: %v\nStack: %s", err, string(debug.Stack()))
		}
	}()

	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case data := <-h.updateChan:
			h.hostsMu.Lock()
			prev, exists := h.hosts[data.HostID]
			if exists {
				timeDiff := data.LastUpdated - prev.LastUpdated
				if timeDiff > 0 {
					data.NetRxRate = (data.NetRx - prev.NetRx) / uint64(timeDiff)
					data.NetTxRate = (data.NetTx - prev.NetTx) / uint64(timeDiff)

					for i, iface := range data.Interfaces {
						for _, prevIface := range prev.Interfaces {
							if prevIface.Name == iface.Name {
								if iface.Rx >= prevIface.Rx {
									data.Interfaces[i].RxRate = (iface.Rx - prevIface.Rx) / uint64(timeDiff)
								}
								if iface.Tx >= prevIface.Tx {
									data.Interfaces[i].TxRate = (iface.Tx - prevIface.Tx) / uint64(timeDiff)
								}
								break
							}
						}
					}
				}
			}
			finalData := data
			h.hosts[data.HostID] = &finalData
			h.hostsMu.Unlock()

			h.broadcast()

		case event := <-h.agentEventChan:
			h.hostsMu.Lock()
			if host, ok := h.hosts[event.HostID]; ok {
				host.AgentUpdateStatus = event.Message
			}
			h.hostsMu.Unlock()
			h.broadcastAgentEvent(event)

		case <-ticker.C:
			// periodic tick
		}
	}
}

func (h *Hub) Update(data MetricData) {
	data.LastUpdated = time.Now().Unix()
	h.updateChan <- data
}

func (h *Hub) AgentEvent(event AgentEvent) {
	h.agentEventChan <- event
}

func (h *Hub) RemoveHost(hostID uint) {
	h.hostsMu.Lock()
	delete(h.hosts, hostID)
	h.hostsMu.Unlock()
	h.broadcastRemove(hostID)
}

func (h *Hub) clientMayViewHost(client *wsClient, hostID uint) bool {
	if client.isAdmin {
		return true
	}
	if client.allowed == nil {
		return false
	}
	return client.allowed[hostID]
}

func (h *Hub) filterHostsForClient(client *wsClient, hosts []*MetricData) []*MetricData {
	out := make([]*MetricData, 0, len(hosts))
	for _, v := range hosts {
		if h.clientMayViewHost(client, v.HostID) {
			out = append(out, v)
		}
	}
	return out
}

func (h *Hub) broadcastRemove(hostID uint) {
	msg := map[string]interface{}{
		"type": "remove",
		"data": hostID,
	}
	jsonMsg, _ := json.Marshal(msg)

	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()
	for client := range h.clients {
		if !h.clientMayViewHost(client, hostID) {
			continue
		}
		client.conn.WriteMessage(websocket.TextMessage, jsonMsg)
	}
}

func (h *Hub) broadcastAgentEvent(event AgentEvent) {
	msg := map[string]interface{}{
		"type": "agent_event",
		"data": event,
	}
	jsonMsg, _ := json.Marshal(msg)

	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()
	for client := range h.clients {
		if !h.clientMayViewHost(client, event.HostID) {
			continue
		}
		client.conn.WriteMessage(websocket.TextMessage, jsonMsg)
	}
}

// Register attaches a dashboard client. allowedHosts nil means admin (all hosts).
func (h *Hub) Register(conn *websocket.Conn, allowedHosts map[uint]bool, isAdmin bool) {
	client := &wsClient{
		conn:    conn,
		isAdmin: isAdmin,
		allowed: allowedHosts,
	}

	h.clientsMu.Lock()
	h.clients[client] = true
	h.clientsMu.Unlock()

	h.hostsMu.RLock()
	hostsList := make([]*MetricData, 0, len(h.hosts))
	for _, v := range h.hosts {
		hostsList = append(hostsList, v)
	}
	h.hostsMu.RUnlock()

	hostsList = h.filterHostsForClient(client, hostsList)

	jsonMsg, _ := json.Marshal(map[string]interface{}{
		"type": "init",
		"data": hostsList,
	})
	conn.WriteMessage(websocket.TextMessage, jsonMsg)
}

func (h *Hub) Unregister(conn *websocket.Conn) {
	h.clientsMu.Lock()
	for client := range h.clients {
		if client.conn == conn {
			delete(h.clients, client)
			break
		}
	}
	h.clientsMu.Unlock()
	conn.Close()
}

func (h *Hub) broadcast() {
	h.hostsMu.RLock()
	allHosts := make([]*MetricData, 0, len(h.hosts))
	for _, v := range h.hosts {
		if time.Now().Unix()-v.LastUpdated < 15 {
			allHosts = append(allHosts, v)
		}
	}
	h.hostsMu.RUnlock()

	h.clientsMu.RLock()
	var toRemove []*wsClient
	for client := range h.clients {
		filtered := h.filterHostsForClient(client, allHosts)
		msg := map[string]interface{}{
			"type": "update",
			"data": filtered,
		}
		jsonMsg, err := json.Marshal(msg)
		if err != nil {
			continue
		}
		if err := client.conn.WriteMessage(websocket.TextMessage, jsonMsg); err != nil {
			toRemove = append(toRemove, client)
		}
	}
	h.clientsMu.RUnlock()

	if len(toRemove) > 0 {
		h.clientsMu.Lock()
		for _, client := range toRemove {
			client.conn.Close()
			delete(h.clients, client)
		}
		h.clientsMu.Unlock()
	}
}
