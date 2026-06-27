//go:build linux

package firewall

import (
	"errors"
	"fmt"
	"reflect"
	"testing"
)

func TestEnsureLibvirtForwardChainRules_RepairsMissingOIFWhenIIFExists(t *testing.T) {
	existing := map[string]bool{
		"termiscope-libvirt-fwd-virbr0": true,
	}
	var added []string

	err := ensureLibvirtForwardChainRules(
		[]string{"virbr0"},
		func(comment string) bool { return existing[comment] },
		func(ifaceDirection, bridge, comment string) error {
			added = append(added, fmt.Sprintf("%s:%s:%s", ifaceDirection, bridge, comment))
			existing[comment] = true
			return nil
		},
	)
	if err != nil {
		t.Fatalf("ensureLibvirtForwardChainRules() error = %v", err)
	}

	want := []string{
		"oifname:virbr0:termiscope-libvirt-fwd-out-virbr0",
	}
	if !reflect.DeepEqual(added, want) {
		t.Fatalf("unexpected added rules:\n got: %v\nwant: %v", added, want)
	}
}

func TestEnsureLibvirtForwardChainRules_AddsBothDirectionsWhenMissing(t *testing.T) {
	var added []string

	err := ensureLibvirtForwardChainRules(
		[]string{"virbr1"},
		func(string) bool { return false },
		func(ifaceDirection, bridge, comment string) error {
			added = append(added, fmt.Sprintf("%s:%s:%s", ifaceDirection, bridge, comment))
			return nil
		},
	)
	if err != nil {
		t.Fatalf("ensureLibvirtForwardChainRules() error = %v", err)
	}

	want := []string{
		"iifname:virbr1:termiscope-libvirt-fwd-virbr1",
		"oifname:virbr1:termiscope-libvirt-fwd-out-virbr1",
	}
	if !reflect.DeepEqual(added, want) {
		t.Fatalf("unexpected added rules:\n got: %v\nwant: %v", added, want)
	}
}

func TestEnsureLibvirtForwardChainRules_NoopWhenBothExist(t *testing.T) {
	existing := map[string]bool{
		"termiscope-libvirt-fwd-virbr0":     true,
		"termiscope-libvirt-fwd-out-virbr0": true,
	}
	called := false

	err := ensureLibvirtForwardChainRules(
		[]string{"virbr0"},
		func(comment string) bool { return existing[comment] },
		func(ifaceDirection, bridge, comment string) error {
			called = true
			return nil
		},
	)
	if err != nil {
		t.Fatalf("ensureLibvirtForwardChainRules() error = %v", err)
	}
	if called {
		t.Fatal("expected no rule additions when both comments exist")
	}
}

func TestEnsureLibvirtForwardChainRules_PropagatesAddError(t *testing.T) {
	wantErr := errors.New("nft failure")
	err := ensureLibvirtForwardChainRules(
		[]string{"virbr2"},
		func(string) bool { return false },
		func(ifaceDirection, bridge, comment string) error {
			if ifaceDirection == "iifname" {
				return wantErr
			}
			return nil
		},
	)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected error %v, got %v", wantErr, err)
	}
}
