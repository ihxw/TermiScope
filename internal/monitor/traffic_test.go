package monitor

import "testing"

func TestIsVirtualInterface(t *testing.T) {
	cases := map[string]bool{
		"lo": true, "eth0": false, "docker0": true, "vethabc": true,
		"br-123": true, "ens33": false, "wlan0": false,
	}
	for name, want := range cases {
		if got := IsVirtualInterface(name); got != want {
			t.Errorf("IsVirtualInterface(%q) = %v, want %v", name, got, want)
		}
	}
}

func TestComputeTrafficTotals_autoFiltersVirtual(t *testing.T) {
	data := MetricData{
		NetRx: 1000,
		NetTx: 2000,
		Interfaces: []InterfaceData{
			{Name: "eth0", Rx: 100, Tx: 200},
			{Name: "docker0", Rx: 900, Tx: 1800},
		},
	}
	rx, tx := ComputeTrafficTotals("auto", data)
	if rx != 100 || tx != 200 {
		t.Fatalf("auto totals = (%d,%d), want (100,200)", rx, tx)
	}
}

func TestComputeTrafficDelta_baselineRealign(t *testing.T) {
	dRx, dTx := ComputeTrafficDelta(500, 500, 100, 100, 3600, 1)
	if dRx != 0 || dTx != 0 {
		t.Fatalf("expected 0 delta on filter change, got (%d,%d)", dRx, dTx)
	}
}

func TestComputeTrafficDelta_reboot(t *testing.T) {
	dRx, _ := ComputeTrafficDelta(500, 0, 50, 0, 120, 1)
	if dRx != 50 {
		t.Fatalf("reboot delta rx = %d, want 50", dRx)
	}
}

func TestSafeRate_underflow(t *testing.T) {
	if SafeRate(100, 200, 2) != 0 {
		t.Fatal("expected 0 rate when counter drops")
	}
	if SafeRate(300, 100, 2) != 100 {
		t.Fatalf("expected 100 B/s, got %d", SafeRate(300, 100, 2))
	}
}

func TestNormalizeTrafficCounterMode(t *testing.T) {
	cases := map[string]string{
		"":       "total",
		"total":  "total",
		"both":   "total",
		" rx ":   "rx",
		"TX":     "tx",
		"broken": "total",
	}
	for input, want := range cases {
		if got := NormalizeTrafficCounterMode(input); got != want {
			t.Fatalf("NormalizeTrafficCounterMode(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestBillableTraffic(t *testing.T) {
	if got := BillableTraffic("rx", 10, 20); got != 10 {
		t.Fatalf("rx billable = %d, want 10", got)
	}
	if got := BillableTraffic("tx", 10, 20); got != 20 {
		t.Fatalf("tx billable = %d, want 20", got)
	}
	if got := BillableTraffic("both", 10, 20); got != 30 {
		t.Fatalf("both billable = %d, want 30", got)
	}
}
