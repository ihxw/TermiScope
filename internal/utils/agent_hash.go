package utils

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"os"
	"path/filepath"
)

type AgentHashInfo struct {
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

const agentHashesFile = "agent_hashes.json"

// agentHashesNeedRegen returns true when cache is missing or any agent binary is newer than the cache file.
func agentHashesNeedRegen() bool {
	cacheInfo, cacheErr := os.Stat(agentHashesFile)
	agentsDir := "agents"
	dirInfo, dirErr := os.Stat(agentsDir)
	if dirErr != nil {
		return false
	}
	if cacheErr != nil {
		return true
	}
	if dirInfo.ModTime().After(cacheInfo.ModTime()) {
		return true
	}

	entries, err := os.ReadDir(agentsDir)
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if len(name) < 16 || name[:16] != "termiscope-agent" {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		if info.ModTime().After(cacheInfo.ModTime()) {
			return true
		}
	}
	return false
}

// EnsureAgentHashesFresh regenerates agent_hashes.json only when agents/ changed since last run.
func EnsureAgentHashesFresh() error {
	if !agentHashesNeedRegen() {
		return nil
	}
	return GenerateAgentHashes()
}

// GenerateAgentHashes generates hashes for all agent binaries in the agents/ directory
// and saves them to agent_hashes.json in the current directory.
func GenerateAgentHashes() error {
	agentsDir := "agents"
	hashes := make(map[string]AgentHashInfo)

	files, err := os.ReadDir(agentsDir)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Agents directory '%s' does not exist, skipping hash generation", agentsDir)
			return nil
		}
		return err
	}

	for _, file := range files {
		if file.IsDir() {
			continue
		}

		filename := file.Name()
		if len(filename) >= 16 && filename[:16] == "termiscope-agent" {
			filePath := filepath.Join(agentsDir, filename)
			sha256Str, size, err := computeFileSHA256(filePath)
			if err != nil {
				log.Printf("Failed to hash agent file %s: %v", filename, err)
				continue
			}

			hashes[filename] = AgentHashInfo{
				SHA256: sha256Str,
				Size:   size,
			}
		}
	}

	data, err := json.MarshalIndent(hashes, "", "  ")
	if err != nil {
		return err
	}

	if err := os.WriteFile(agentHashesFile, data, 0644); err != nil {
		return err
	}

	log.Printf("Successfully generated hashes for %d agent files in %s", len(hashes), agentHashesFile)
	return nil
}

// GetAgentHashInfo retrieves hash info for a specific agent file, refreshing cache if needed.
func GetAgentHashInfo(filename string) (*AgentHashInfo, error) {
	if err := EnsureAgentHashesFresh(); err != nil {
		return nil, err
	}

	data, err := os.ReadFile(agentHashesFile)
	if err != nil {
		return nil, err
	}

	var hashes map[string]AgentHashInfo
	if err := json.Unmarshal(data, &hashes); err != nil {
		return nil, err
	}

	info, exists := hashes[filename]
	if !exists {
		if genErr := GenerateAgentHashes(); genErr != nil {
			return nil, genErr
		}
		data, err = os.ReadFile(agentHashesFile)
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(data, &hashes); err != nil {
			return nil, err
		}
		info, exists = hashes[filename]
		if !exists {
			return nil, os.ErrNotExist
		}
	}

	return &info, nil
}

func computeFileSHA256(filePath string) (string, int64, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return "", 0, err
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		return "", 0, err
	}

	hasher := sha256.New()
	if _, err := io.Copy(hasher, f); err != nil {
		return "", 0, err
	}

	return hex.EncodeToString(hasher.Sum(nil)), info.Size(), nil
}
