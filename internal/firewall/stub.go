//go:build !linux && !windows

package firewall

import "fmt"

type stubManager struct{}

func (m *stubManager) Status() (Status, error) {
	return finalizeStatus(Status{
		Available: false,
		Backend:   "none",
		Message:   "firewall management is not supported on this platform",
	}), nil
}

func (m *stubManager) Rules() ([]Rule, error) {
	return nil, fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) AddRule(_ AddRuleRequest) error {
	return fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) DeleteRule(_ int) error {
	return fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) PortForwards() ([]PortForwardRule, error) {
	return nil, fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) AddPortForward(_ AddPortForwardRequest) error {
	return fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) DeletePortForward(_ int) error {
	return fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) GetPortForwardSettings() (PortForwardSettings, error) {
	return PortForwardSettings{}, nil
}

func (m *stubManager) UpdatePortForwardSettings(_ UpdatePortForwardSettingsRequest) error {
	return fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) Enable(_ EnableFirewallRequest) error {
	return fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) ExternalAccessPorts(_ string) ([]ExternalAccessPort, error) {
	return nil, fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) Disable() error {
	return fmt.Errorf("firewall management is not supported on this platform")
}

func (m *stubManager) Initialize() error {
	return fmt.Errorf("firewall management is not supported on this platform")
}
