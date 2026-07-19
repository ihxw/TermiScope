package monitor

import (
	"encoding/json"
	"runtime/debug"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/ihxw/termiscope/internal/utils"
)

const (
	hostSoftOfflineSeconds = 15
	hostStaleSeconds       = 60
	broadcastDebounce      = 300 * time.Millisecond
	clientWriteTimeout     = 5 * time.Second
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
	HostID                  uint    `json:"host_id"`
	Timestamp               int64   `json:"timestamp"` // Unix Timestamp
	AgentVersion            string  `json:"agent_version"`
	AgentTransferPort       int     `json:"agent_transfer_port,omitempty"`
	AgentTransferCertSHA256 string  `json:"agent_transfer_cert_sha256,omitempty"`
	AgentTransferRelay      bool    `json:"agent_transfer_relay,omitempty"`
	Uptime                  uint64  `json:"uptime"` // Seconds
	CPU                     float64 `json:"cpu"`    // Percentage
	CpuCount                int     `json:"cpu_count"`
	CpuModel                string  `json:"cpu_model"`
	CpuMhz                  float64 `json:"cpu_mhz"`
	MemUsed                 uint64  `json:"mem_used"`    // Bytes
	MemTotal                uint64  `json:"mem_total"`   // Bytes
	DiskUsed                uint64  `json:"disk_used"`   // Bytes
	DiskTotal               uint64  `json:"disk_total"`  // Bytes
	NetRx                   uint64  `json:"net_rx"`      // Total Bytes In
	NetTx                   uint64  `json:"net_tx"`      // Total Bytes Out
	NetRxRate               uint64  `json:"net_rx_rate"` // Bytes/sec (Total)
	NetTxRate               uint64  `json:"net_tx_rate"` // Bytes/sec (Total)
	NetMonthlyRx            uint64  `json:"net_monthly_rx"`
	NetMonthlyTx            uint64  `json:"net_monthly_tx"`
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
	conn    *websocket.Conn
	isAdmin bool
	allowed map[uint]bool // nil = admin (all hosts)
	writeMu sync.Mutex
}

type Hub struct {
	clients   map[*wsClient]bool
	clientsMu sync.RWMutex

	hosts   map[uint]*MetricData
	hostsMu sync.RWMutex

	updateChan     chan MetricData
	agentEventChan chan AgentEvent

	pendingMu      sync.Mutex
	pendingUpdates map[uint]MetricData
	offlineHosts   map[uint]bool
	dirtyHosts     map[uint]bool

	broadcastMu        sync.Mutex
	broadcastScheduled bool
}

var GlobalHub = NewHub()

func NewHub() *Hub {
	return &Hub{
		clients:        make(map[*wsClient]bool),
		hosts:          make(map[uint]*MetricData),
		updateChan:     make(chan MetricData, 256),
		agentEventChan: make(chan AgentEvent, 64),
		pendingUpdates: make(map[uint]MetricData),
		offlineHosts:   make(map[uint]bool),
		dirtyHosts:     make(map[uint]bool),
	}
}

func (h *Hub) Run() {
	defer func() {
		if err := recover(); err != nil {
			utils.LogError("Monitor Hub Panic: %v\nStack: %s", err, string(debug.Stack()))
		}
	}()

	staleTicker := time.NewTicker(5 * time.Second)
	defer staleTicker.Stop()

	for {
		select {
		case data := <-h.updateChan:
			h.applyUpdate(data)
			h.markDirty(data.HostID)

		case event := <-h.agentEventChan:
			h.hostsMu.Lock()
			if host, ok := h.hosts[event.HostID]; ok {
				host.AgentUpdateStatus = event.Message
			}
			h.hostsMu.Unlock()
			h.markDirty(event.HostID)
			h.broadcastAgentEvent(event)

		case <-staleTicker.C:
			h.markSoftOfflineHosts()
			h.evictStaleHosts()
			h.flushPendingUpdates()
		}
	}
}

func (h *Hub) applyInterfaceRates(data *MetricData, prev *MetricData) {
	timeDiff := data.LastUpdated - prev.LastUpdated
	if timeDiff <= 0 {
		return
	}
	data.NetRxRate = SafeRate(data.NetRx, prev.NetRx, uint64(timeDiff))
	data.NetTxRate = SafeRate(data.NetTx, prev.NetTx, uint64(timeDiff))

	prevByName := make(map[string]InterfaceData, len(prev.Interfaces))
	for _, p := range prev.Interfaces {
		prevByName[p.Name] = p
	}
	for i, iface := range data.Interfaces {
		if prevIface, ok := prevByName[iface.Name]; ok {
			data.Interfaces[i].RxRate = SafeRate(iface.Rx, prevIface.Rx, uint64(timeDiff))
			data.Interfaces[i].TxRate = SafeRate(iface.Tx, prevIface.Tx, uint64(timeDiff))
		}
	}
}

func (h *Hub) applyUpdate(data MetricData) {
	h.hostsMu.Lock()
	defer h.hostsMu.Unlock()

	prev, exists := h.hosts[data.HostID]
	if exists {
		data = mergeMetricData(prev, data)
		h.applyInterfaceRates(&data, prev)
	}
	finalData := data
	h.hosts[data.HostID] = &finalData
	delete(h.offlineHosts, data.HostID)
}

func (h *Hub) markDirty(hostID uint) {
	h.broadcastMu.Lock()
	h.dirtyHosts[hostID] = true
	if !h.broadcastScheduled {
		h.broadcastScheduled = true
		go func() {
			time.Sleep(broadcastDebounce)
			h.broadcastMu.Lock()
			h.broadcastScheduled = false
			h.broadcastMu.Unlock()
			h.broadcastDirty()
		}()
	}
	h.broadcastMu.Unlock()
}

func (h *Hub) enqueueUpdate(data MetricData) {
	select {
	case h.updateChan <- data:
	default:
		h.pendingMu.Lock()
		h.pendingUpdates[data.HostID] = data
		h.pendingMu.Unlock()
	}
}

func (h *Hub) flushPendingUpdates() {
	h.pendingMu.Lock()
	if len(h.pendingUpdates) == 0 {
		h.pendingMu.Unlock()
		return
	}
	pending := h.pendingUpdates
	h.pendingUpdates = make(map[uint]MetricData)
	h.pendingMu.Unlock()

	for _, data := range pending {
		data.LastUpdated = time.Now().Unix()
		h.applyUpdate(data)
		h.markDirty(data.HostID)
	}
}

func (h *Hub) markSoftOfflineHosts() {
	now := time.Now().Unix()
	h.hostsMu.Lock()
	var offline []uint
	for id, v := range h.hosts {
		if now-v.LastUpdated > hostSoftOfflineSeconds && !h.offlineHosts[id] {
			h.offlineHosts[id] = true
			offline = append(offline, id)
		}
	}
	h.hostsMu.Unlock()

	for _, id := range offline {
		h.broadcastOffline(id)
	}
}

func (h *Hub) evictStaleHosts() {
	now := time.Now().Unix()
	h.hostsMu.Lock()
	for id, v := range h.hosts {
		if now-v.LastUpdated > hostStaleSeconds {
			delete(h.hosts, id)
			delete(h.offlineHosts, id)
		}
	}
	h.hostsMu.Unlock()
}

func (h *Hub) Update(data MetricData) {
	data.LastUpdated = time.Now().Unix()
	h.enqueueUpdate(data)
}

func (h *Hub) AgentEvent(event AgentEvent) {
	select {
	case h.agentEventChan <- event:
	default:
	}
}

func (h *Hub) RemoveHost(hostID uint) {
	h.hostsMu.Lock()
	delete(h.hosts, hostID)
	delete(h.offlineHosts, hostID)
	h.hostsMu.Unlock()
	notifyHostRemoved(hostID)
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
	now := time.Now().Unix()
	for _, v := range hosts {
		if now-v.LastUpdated <= hostSoftOfflineSeconds && h.clientMayViewHost(client, v.HostID) {
			out = append(out, v)
		}
	}
	return out
}

func (c *wsClient) writeMessage(jsonMsg []byte) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_ = c.conn.SetWriteDeadline(time.Now().Add(clientWriteTimeout))
	return c.conn.WriteMessage(websocket.TextMessage, jsonMsg)
}

func (h *Hub) clientsForHost(hostID uint) []*wsClient {
	h.clientsMu.RLock()
	clients := make([]*wsClient, 0, len(h.clients))
	for client := range h.clients {
		if h.clientMayViewHost(client, hostID) {
			clients = append(clients, client)
		}
	}
	h.clientsMu.RUnlock()
	return clients
}

func (h *Hub) snapshotClients() []*wsClient {
	h.clientsMu.RLock()
	clients := make([]*wsClient, 0, len(h.clients))
	for client := range h.clients {
		clients = append(clients, client)
	}
	h.clientsMu.RUnlock()
	return clients
}

func (h *Hub) removeClients(clients []*wsClient) {
	if len(clients) == 0 {
		return
	}
	h.clientsMu.Lock()
	for _, client := range clients {
		if _, ok := h.clients[client]; ok {
			delete(h.clients, client)
			client.conn.Close()
		}
	}
	h.clientsMu.Unlock()
}

func (h *Hub) broadcastHostEvent(eventType string, hostID uint) {
	msg := map[string]interface{}{
		"type": eventType,
		"data": hostID,
	}
	jsonMsg, _ := json.Marshal(msg)

	var toRemove []*wsClient
	for _, client := range h.clientsForHost(hostID) {
		if err := client.writeMessage(jsonMsg); err != nil {
			toRemove = append(toRemove, client)
		}
	}
	h.removeClients(toRemove)
}

func (h *Hub) broadcastOffline(hostID uint) {
	h.broadcastHostEvent("offline", hostID)
}

func (h *Hub) broadcastRemove(hostID uint) {
	h.broadcastHostEvent("remove", hostID)
}

func (h *Hub) broadcastAgentEvent(event AgentEvent) {
	msg := map[string]interface{}{
		"type": "agent_event",
		"data": event,
	}
	jsonMsg, _ := json.Marshal(msg)

	var toRemove []*wsClient
	for _, client := range h.clientsForHost(event.HostID) {
		if err := client.writeMessage(jsonMsg); err != nil {
			toRemove = append(toRemove, client)
		}
	}
	h.removeClients(toRemove)
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
	if err := client.writeMessage(jsonMsg); err != nil {
		h.removeClients([]*wsClient{client})
	}
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

func (h *Hub) broadcastDirty() {
	h.broadcastMu.Lock()
	if len(h.dirtyHosts) == 0 {
		h.broadcastMu.Unlock()
		return
	}
	dirtyIDs := make([]uint, 0, len(h.dirtyHosts))
	for id := range h.dirtyHosts {
		dirtyIDs = append(dirtyIDs, id)
	}
	h.dirtyHosts = make(map[uint]bool)
	h.broadcastMu.Unlock()

	h.hostsMu.RLock()
	changed := make([]*MetricData, 0, len(dirtyIDs))
	now := time.Now().Unix()
	for _, id := range dirtyIDs {
		if v, ok := h.hosts[id]; ok && now-v.LastUpdated <= hostSoftOfflineSeconds {
			changed = append(changed, v)
		}
	}
	h.hostsMu.RUnlock()

	if len(changed) == 0 {
		return
	}

	var toRemove []*wsClient
	for _, client := range h.snapshotClients() {
		filtered := h.filterHostsForClient(client, changed)
		if len(filtered) == 0 {
			continue
		}
		msg := map[string]interface{}{
			"type": "update",
			"data": filtered,
		}
		jsonMsg, err := json.Marshal(msg)
		if err != nil {
			continue
		}
		if err := client.writeMessage(jsonMsg); err != nil {
			toRemove = append(toRemove, client)
		}
	}
	h.removeClients(toRemove)
}
