package middleware

import (
	"strings"
	"testing"
)

func TestSanitizeRawQueryRedactsSensitiveValues(t *testing.T) {
	got := sanitizeRawQuery("token=abc&ticket=def&secret=ghi&password=jkl&host_id=42")

	for _, leaked := range []string{"abc", "def", "ghi", "jkl"} {
		if strings.Contains(got, leaked) {
			t.Fatalf("sanitized query leaked %q: %s", leaked, got)
		}
	}
	if !strings.Contains(got, "host_id=42") {
		t.Fatalf("sanitized query removed safe parameter: %s", got)
	}
	if strings.Count(got, "REDACTED") != 4 {
		t.Fatalf("sanitized query should redact 4 values: %s", got)
	}
}
