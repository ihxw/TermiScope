package updater

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCheckForUpdateAllowsUntrustedReleaseWithoutChecksum(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{
			"tag_name": "v1.7.1",
			"name": "v1.7.1",
			"body": "release notes",
			"assets": [
				{
					"name": "TermiScope-1.7.1-linux-amd64.tar.gz",
					"browser_download_url": "https://github.com/ihxw/TermiScope/releases/download/v1.7.1/TermiScope-1.7.1-linux-amd64.tar.gz",
					"size": 123
				}
			]
		}`)
	}))
	defer server.Close()

	restore := overrideLatestReleaseURLForTest(t, server.URL)
	defer restore()

	info, err := CheckForUpdate("1.7.0")
	if err != nil {
		t.Fatalf("check update: %v", err)
	}
	if info == nil {
		t.Fatalf("expected update info")
	}
	if info.Trusted {
		t.Fatalf("Trusted = true, want false")
	}
	if info.ChecksumError == "" || !strings.Contains(info.ChecksumError, "trusted checksum asset") {
		t.Fatalf("ChecksumError = %q, want trusted checksum error", info.ChecksumError)
	}
	if info.AssetName != "TermiScope-1.7.1-linux-amd64.tar.gz" {
		t.Fatalf("AssetName = %q", info.AssetName)
	}
}

func TestCheckForTrustedUpdateRequiresChecksum(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{
			"tag_name": "v1.7.1",
			"name": "v1.7.1",
			"body": "release notes",
			"assets": [
				{
					"name": "TermiScope-1.7.1-linux-amd64.tar.gz",
					"browser_download_url": "https://github.com/ihxw/TermiScope/releases/download/v1.7.1/TermiScope-1.7.1-linux-amd64.tar.gz",
					"size": 123
				}
			]
		}`)
	}))
	defer server.Close()

	restore := overrideLatestReleaseURLForTest(t, server.URL)
	defer restore()

	_, err := CheckForTrustedUpdate("1.7.0")
	if err == nil {
		t.Fatalf("expected checksum error")
	}
	if !strings.Contains(err.Error(), "trusted checksum asset TermiScope-1.7.1-linux-amd64.tar.gz.sha256 is required") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func overrideLatestReleaseURLForTest(t *testing.T, url string) func() {
	t.Helper()
	oldURL := latestReleaseURL
	latestReleaseURL = url
	return func() {
		latestReleaseURL = oldURL
	}
}
