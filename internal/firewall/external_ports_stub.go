//go:build !linux && !windows

package firewall

func detectExternalAccessPorts(clientIP string) ([]ExternalAccessPort, error) {
	return markClientSessionPort(baselineExternalPorts(), clientIP, configuredListenPort()), nil
}
