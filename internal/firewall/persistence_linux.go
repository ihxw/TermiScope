//go:build linux

package firewall

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const nftPersistenceService = "/etc/systemd/system/termiscope-firewall.service"

func ensureNFTBootPersistence(snippetPath string) error {
	if !commandExists("systemctl") {
		return fmt.Errorf("systemd is required to enable nftables boot persistence")
	}
	nftPath, err := exec.LookPath("nft")
	if err != nil {
		return err
	}
	unit := fmt.Sprintf(`[Unit]
Description=Load TermiScope nftables rules
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target
ConditionPathExists=%s

[Service]
Type=oneshot
ExecStart=%s -f %s
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
`, snippetPath, nftPath, snippetPath)
	if err := writePrivilegedFile(nftPersistenceService, []byte(unit), 0644); err != nil {
		return err
	}
	if _, err := runCommandPrivileged("systemctl", "daemon-reload"); err != nil {
		return err
	}
	if _, err := runCommandPrivileged("systemctl", "enable", "termiscope-firewall.service"); err != nil {
		return err
	}
	return nil
}

func writePrivilegedFile(path string, data []byte, mode os.FileMode) error {
	if os.Geteuid() == 0 {
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		return os.WriteFile(path, data, mode)
	}
	tmp, err := os.CreateTemp("", "termiscope-firewall-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if _, err := runCommandPrivileged("mkdir", "-p", filepath.Dir(path)); err != nil {
		return err
	}
	_, err = runCommandPrivileged("install", "-m", fmt.Sprintf("%04o", mode.Perm()), tmpPath, path)
	return err
}

func nftPersistenceStatus() (persisted, bootLoaded bool, message string) {
	if _, err := os.Stat("/etc/nftables.d/termiscope.nft"); err == nil {
		persisted = true
	} else {
		message = "TermiScope nftables snippet is not written"
	}
	if !commandExists("systemctl") {
		if message != "" {
			message += "; "
		}
		message += "systemd is not available for boot persistence"
		return persisted, false, message
	}
	out, err := runCommand("systemctl", "is-enabled", "termiscope-firewall.service")
	if err == nil && strings.TrimSpace(out) == "enabled" {
		bootLoaded = true
	} else {
		if message != "" {
			message += "; "
		}
		message += "TermiScope firewall boot service is not enabled"
	}
	return persisted, bootLoaded, message
}
