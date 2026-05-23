//go:build linux

package firewall

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

type linuxDistro struct {
	ID           string
	IDLike       string
	VersionID    string
	PackageMgr   string
	InstallCmd   []string
}

func detectDistro() linuxDistro {
	d := linuxDistro{PackageMgr: "unknown"}
	f, err := os.Open("/etc/os-release")
	if err != nil {
		return d
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	kv := map[string]string{}
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := parts[0]
		val := strings.Trim(strings.TrimSpace(parts[1]), `"`)
		kv[key] = val
	}

	d.ID = strings.ToLower(kv["ID"])
	d.IDLike = strings.ToLower(kv["ID_LIKE"])
	d.VersionID = kv["VERSION_ID"]

	switch {
	case d.ID == "ubuntu" || d.ID == "debian" || strings.Contains(d.IDLike, "debian"):
		d.PackageMgr = "apt"
		d.InstallCmd = []string{"apt-get", "install", "-y", "nftables"}
	case d.ID == "fedora" || d.ID == "rhel" || d.ID == "centos" || d.ID == "rocky" || d.ID == "almalinux" || strings.Contains(d.IDLike, "rhel") || strings.Contains(d.IDLike, "fedora"):
		if commandExists("dnf") {
			d.PackageMgr = "dnf"
			d.InstallCmd = []string{"dnf", "install", "-y", "nftables"}
		} else {
			d.PackageMgr = "yum"
			d.InstallCmd = []string{"yum", "install", "-y", "nftables"}
		}
	case d.ID == "arch" || d.ID == "manjaro" || strings.Contains(d.IDLike, "arch"):
		d.PackageMgr = "pacman"
		d.InstallCmd = []string{"pacman", "-Sy", "--noconfirm", "nftables"}
	case d.ID == "alpine":
		d.PackageMgr = "apk"
		d.InstallCmd = []string{"apk", "add", "--no-cache", "nftables"}
	case d.ID == "opensuse-leap" || d.ID == "opensuse-tumbleweed" || d.ID == "sles" || strings.Contains(d.IDLike, "suse"):
		d.PackageMgr = "zypper"
		d.InstallCmd = []string{"zypper", "-n", "install", "nftables"}
	default:
		if commandExists("apt-get") {
			d.PackageMgr = "apt"
			d.InstallCmd = []string{"apt-get", "install", "-y", "nftables"}
		} else if commandExists("dnf") {
			d.PackageMgr = "dnf"
			d.InstallCmd = []string{"dnf", "install", "-y", "nftables"}
		} else if commandExists("yum") {
			d.PackageMgr = "yum"
			d.InstallCmd = []string{"yum", "install", "-y", "nftables"}
		} else if commandExists("apk") {
			d.PackageMgr = "apk"
			d.InstallCmd = []string{"apk", "add", "--no-cache", "nftables"}
		}
	}

	return d
}

func installNftables() error {
	if commandExists("nft") {
		return nil
	}

	distro := detectDistro()
	if len(distro.InstallCmd) == 0 {
		return fmt.Errorf("unsupported linux distribution for automatic nftables installation (ID=%s)", distro.ID)
	}

	if distro.PackageMgr == "apt" {
		if _, err := runCommandPrivileged("apt-get", "update"); err != nil {
			// non-fatal: mirror may still have nftables cached
		}
	}

	if _, err := runCommandPrivileged(distro.InstallCmd[0], distro.InstallCmd[1:]...); err != nil {
		return fmt.Errorf("install nftables via %s: %w", distro.PackageMgr, err)
	}

	if !commandExists("nft") {
		return fmt.Errorf("nftables installed but nft command not found in PATH")
	}

	// Do not start the distro nftables service here — it may load /etc/nftables.conf and
	// conflict with TermiScope rules. TermiScope persists its own snippet when rules change.

	return nil
}
