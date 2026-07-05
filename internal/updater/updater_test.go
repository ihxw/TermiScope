package updater

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"testing"
)

func TestCheckForUpdateAllowsUntrustedReleaseWithoutChecksum(t *testing.T) {
	assetName := compatibleAssetNameForTest(t, "1.7.1")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `{
			"tag_name": "v1.7.1",
			"name": "v1.7.1",
			"body": "release notes",
			"assets": [
				{
					"name": "%s",
					"browser_download_url": "https://github.com/ihxw/TermiScope/releases/download/v1.7.1/%s",
					"size": 123
				}
			]
		}`, assetName, assetName)
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
	if info.AssetName != assetName {
		t.Fatalf("AssetName = %q", info.AssetName)
	}
}

func TestCheckForTrustedUpdateRequiresChecksum(t *testing.T) {
	assetName := compatibleAssetNameForTest(t, "1.7.1")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `{
			"tag_name": "v1.7.1",
			"name": "v1.7.1",
			"body": "release notes",
			"assets": [
				{
					"name": "%s",
					"browser_download_url": "https://github.com/ihxw/TermiScope/releases/download/v1.7.1/%s",
					"size": 123
				}
			]
		}`, assetName, assetName)
	}))
	defer server.Close()

	restore := overrideLatestReleaseURLForTest(t, server.URL)
	defer restore()

	_, err := CheckForTrustedUpdate("1.7.0")
	if err == nil {
		t.Fatalf("expected checksum error")
	}
	if !strings.Contains(err.Error(), "trusted checksum asset "+assetName+".sha256 is required") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func compatibleAssetNameForTest(t *testing.T, version string) string {
	t.Helper()

	arch := runtime.GOARCH
	switch arch {
	case "amd64", "arm64":
	default:
		t.Skipf("unsupported updater test architecture %s", arch)
	}

	ext := ".tar.gz"
	if runtime.GOOS == "windows" {
		ext = ".zip"
	}
	return fmt.Sprintf("TermiScope-%s-%s-%s%s", version, runtime.GOOS, arch, ext)
}

func overrideLatestReleaseURLForTest(t *testing.T, url string) func() {
	t.Helper()
	oldURL := latestReleaseURL
	latestReleaseURL = url
	return func() {
		latestReleaseURL = oldURL
	}
}
