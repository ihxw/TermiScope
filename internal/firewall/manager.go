package firewall

import "sync"

var (
	managerOnce sync.Once
	managerInst Manager
)

// NewManager returns a process-wide firewall manager.
func NewManager() Manager {
	managerOnce.Do(func() {
		managerInst = &lockedManager{inner: newPlatformManager()}
	})
	return managerInst
}

type lockedManager struct {
	inner Manager
	mu    sync.Mutex
}

func (m *lockedManager) Status() (Status, error) {
	return m.inner.Status()
}

func (m *lockedManager) Rules() ([]Rule, error) {
	return m.inner.Rules()
}

func (m *lockedManager) PortForwards() ([]PortForwardRule, error) {
	return m.inner.PortForwards()
}

func (m *lockedManager) GetPortForwardSettings() (PortForwardSettings, error) {
	return m.inner.GetPortForwardSettings()
}

func (m *lockedManager) ExternalAccessPorts(clientIP string) ([]ExternalAccessPort, error) {
	return m.inner.ExternalAccessPorts(clientIP)
}

func (m *lockedManager) KVMCompatibility() (KVMCompatStatus, error) {
	return m.inner.KVMCompatibility()
}

func (m *lockedManager) AddRule(req AddRuleRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.AddRule(req)
}

func (m *lockedManager) UpdateRule(number int, req AddRuleRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.UpdateRule(number, req)
}

func (m *lockedManager) DeleteRule(number int) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.DeleteRule(number)
}

func (m *lockedManager) AddPortForward(req AddPortForwardRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.AddPortForward(req)
}

func (m *lockedManager) UpdatePortForward(number int, req AddPortForwardRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.UpdatePortForward(number, req)
}

func (m *lockedManager) DeletePortForward(number int) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.DeletePortForward(number)
}

func (m *lockedManager) UpdatePortForwardSettings(req UpdatePortForwardSettingsRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.UpdatePortForwardSettings(req)
}

func (m *lockedManager) Enable(req EnableFirewallRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.Enable(req)
}

func (m *lockedManager) Disable() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.Disable()
}

func (m *lockedManager) Initialize() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.Initialize()
}

func (m *lockedManager) EnsureKVMCompatibility() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.inner.EnsureKVMCompatibility()
}
