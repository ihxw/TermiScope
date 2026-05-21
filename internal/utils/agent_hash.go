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
		// Only hash termiscope-agent-* files
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

	// Save to JSON
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

// GetAgentHashInfo retrieves the hash info for a specific agent file from the cache file.
// If the cache file is missing or the file is not in the cache, it returns an error.
func GetAgentHashInfo(filename string) (*AgentHashInfo, error) {
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
		return nil, os.ErrNotExist
	}

	return &info, nil
}

// computeFileSHA256 computes the SHA256 hash and size of a file
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
