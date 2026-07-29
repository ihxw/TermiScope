package utils

import (
	"fmt"
	"os"
	"path/filepath"
)

// ResolveScriptsFile locates a file under scripts/ for dev trees and release installs.
func ResolveScriptsFile(name string) (string, error) {
	var tried []string
	check := func(p string) (string, bool) {
		tried = append(tried, p)
		if _, err := os.Stat(p); err == nil {
			return p, true
		}
		return "", false
	}

	if p, ok := check(filepath.Join("scripts", name)); ok {
		return p, nil
	}

	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		for _, rel := range []string{
			filepath.Join(dir, "scripts", name),
			filepath.Join(dir, "..", "scripts", name),
		} {
			if p, ok := check(rel); ok {
				return p, nil
			}
		}
	}

	return "", fmt.Errorf("scripts/%s not found (tried %v)", name, tried)
}
