package monitor

import "testing"

func TestMergeMetricDataPreservesStaticFields(t *testing.T) {
	prev := &MetricData{
		HostID:       1,
		OS:           "linux Ubuntu",
		Hostname:     "web-01",
		CpuModel:     "Intel Xeon",
		CpuCount:     4,
		CpuMhz:       2400,
		AgentVersion: "1.0.0",
		Disks: []DiskData{
			{MountPoint: "/", Used: 100, Total: 1000},
		},
		Interfaces: []InterfaceData{
			{Name: "eth0", Rx: 10, Tx: 20, IPs: []string{"10.0.0.1/24"}, Mac: "aa:bb:cc:dd:ee:ff"},
		},
	}

	incoming := MetricData{
		HostID:   1,
		CPU:      12.5,
		MemUsed:  512,
		MemTotal: 1024,
		NetRx:    100,
		NetTx:    200,
		Interfaces: []InterfaceData{
			{Name: "eth0", Rx: 50, Tx: 80},
		},
	}

	merged := mergeMetricData(prev, incoming)

	if merged.OS != prev.OS {
		t.Fatalf("expected OS %q, got %q", prev.OS, merged.OS)
	}
	if merged.Hostname != prev.Hostname {
		t.Fatalf("expected hostname %q, got %q", prev.Hostname, merged.Hostname)
	}
	if merged.CpuModel != prev.CpuModel {
		t.Fatalf("expected cpu model %q, got %q", prev.CpuModel, merged.CpuModel)
	}
	if len(merged.Disks) != 1 || merged.Disks[0].MountPoint != "/" {
		t.Fatalf("expected previous disk list to be preserved")
	}
	if len(merged.Interfaces) != 1 {
		t.Fatalf("expected one interface")
	}
	if merged.Interfaces[0].Rx != 50 || merged.Interfaces[0].Tx != 80 {
		t.Fatalf("expected updated counters")
	}
	if len(merged.Interfaces[0].IPs) != 1 || merged.Interfaces[0].Mac != "aa:bb:cc:dd:ee:ff" {
		t.Fatalf("expected static interface metadata to be preserved")
	}
}

func TestMergeMetricDataFullReportReplacesStaticFields(t *testing.T) {
	prev := &MetricData{
		HostID:   1,
		Hostname: "old-name",
		Disks: []DiskData{
			{MountPoint: "/", Used: 100, Total: 1000},
		},
	}

	incoming := MetricData{
		HostID:   1,
		Hostname: "new-name",
		Disks: []DiskData{
			{MountPoint: "/data", Used: 10, Total: 500},
		},
	}

	merged := mergeMetricData(prev, incoming)
	if merged.Hostname != "new-name" {
		t.Fatalf("expected hostname to be replaced")
	}
	if len(merged.Disks) != 1 || merged.Disks[0].MountPoint != "/data" {
		t.Fatalf("expected incoming disk list to replace previous")
	}
}
