//go:build !linux

package firewall

func libvirtBridgeNames() []string { return nil }

func libvirtNetworkingActive() bool { return false }
