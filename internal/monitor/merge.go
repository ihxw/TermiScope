package monitor

// mergeMetricData overlays a partial agent pulse onto the last known host snapshot.
// Dynamic heartbeats omit static fields; the hub keeps the previous values for the UI.
func mergeMetricData(prev *MetricData, incoming MetricData) MetricData {
	if prev == nil {
		return incoming
	}

	out := incoming

	if out.OS == "" {
		out.OS = prev.OS
	}
	if out.Hostname == "" {
		out.Hostname = prev.Hostname
	}
	if out.CpuModel == "" {
		out.CpuModel = prev.CpuModel
	}
	if out.CpuCount == 0 {
		out.CpuCount = prev.CpuCount
	}
	if out.CpuMhz == 0 {
		out.CpuMhz = prev.CpuMhz
	}
	if out.AgentVersion == "" {
		out.AgentVersion = prev.AgentVersion
	}
	if out.AgentUpdateStatus == "" {
		out.AgentUpdateStatus = prev.AgentUpdateStatus
	}
	if len(out.Disks) == 0 && len(prev.Disks) > 0 {
		out.Disks = prev.Disks
	}

	out.Interfaces = mergeInterfaceData(prev.Interfaces, out.Interfaces)

	return out
}

func mergeInterfaceData(prevIfaces, incomingIfaces []InterfaceData) []InterfaceData {
	if len(incomingIfaces) == 0 {
		return prevIfaces
	}
	if len(prevIfaces) == 0 {
		return incomingIfaces
	}

	prevByName := make(map[string]InterfaceData, len(prevIfaces))
	for _, iface := range prevIfaces {
		prevByName[iface.Name] = iface
	}

	merged := make([]InterfaceData, len(incomingIfaces))
	for i, iface := range incomingIfaces {
		merged[i] = iface
		prevIface, ok := prevByName[iface.Name]
		if !ok {
			continue
		}
		if len(merged[i].IPs) == 0 {
			merged[i].IPs = prevIface.IPs
		}
		if merged[i].Mac == "" {
			merged[i].Mac = prevIface.Mac
		}
	}
	return merged
}
