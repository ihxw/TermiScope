package utils_test

import (
	"testing"

	"github.com/ihxw/termiscope/internal/utils"
)

func TestSanitizeLog(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Password redaction",
			input:    `password=secret123`,
			expected: `password=***REDACTED***`,
		},
		{
			name:     "Token redaction",
			input:    `Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U`,
			expected: `Bearer ***REDACTED***`,
		},
		{
			name:     "API key redaction",
			input:    `api_key=abcd1234`,
			expected: `api_key=***REDACTED***`,
		},
		{
			name:     "Hex key redaction",
			input:    `key: cd10c783bd85d22d2dd1db8c8614db2a`,
			expected: `key=***REDACTED***`,
		},
		{
			name:     "No sensitive data",
			input:    `Normal log message`,
			expected: `Normal log message`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := utils.SanitizeLog(tt.input)
			if result != tt.expected {
				t.Errorf("SanitizeLog(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestShellEscape(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Simple argument",
			input:    "hello",
			expected: "hello",
		},
		{
			name:     "Argument with spaces",
			input:    "hello world",
			expected: "'hello world'",
		},
		{
			name:     "Argument with single quotes",
			input:    "it's",
			expected: "'it'\\''s'",
		},
		{
			name:     "Argument with special chars",
			input:    "$HOME",
			expected: "'$HOME'",
		},
		{
			name:     "Argument with semicolon",
			input:    "file;rm -rf /",
			expected: "'file;rm -rf /'",
		},
		{
			name:     "Empty argument",
			input:    "",
			expected: "''",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := utils.ShellEscape(tt.input)
			if result != tt.expected {
				t.Errorf("ShellEscape(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestValidateShellCommand(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected bool // true if dangerous
	}{
		{
			name:     "Safe command",
			input:    "ls -la",
			expected: false,
		},
		{
			name:     "Command with semicolon",
			input:    "ls; rm -rf /",
			expected: true,
		},
		{
			name:     "Command with pipe",
			input:    "cat file | grep test",
			expected: true,
		},
		{
			name:     "Command with dollar",
			input:    "echo $HOME",
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := utils.ValidateShellCommand(tt.input)
			if result != tt.expected {
				t.Errorf("ValidateShellCommand(%q) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}
