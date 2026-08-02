package main

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

func fetchCountryCode(client *http.Client, endpoint string) (string, error) {
	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "TermiScope-Agent/"+Version)

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("country service returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 16))
	if err != nil {
		return "", err
	}
	code := strings.ToUpper(strings.TrimSpace(string(body)))
	if len(code) != 2 || code[0] < 'A' || code[0] > 'Z' || code[1] < 'A' || code[1] > 'Z' {
		return "", fmt.Errorf("country service returned invalid code %q", code)
	}
	return code, nil
}

func currentCountryCode() string {
	countryMu.RLock()
	defer countryMu.RUnlock()
	return cachedCountry
}

func setCountryCode(code string) {
	countryMu.Lock()
	cachedCountry = code
	countryMu.Unlock()
}

func detectCountryUntilSuccess(stop <-chan struct{}) {
	client := &http.Client{Timeout: 5 * time.Second}
	for {
		code, err := fetchCountryCode(client, countryDetectionURL)
		if err == nil {
			setCountryCode(code)
			return
		}
		logError("Failed to detect country: %v", err)

		timer := time.NewTimer(countryDetectionRetry)
		select {
		case <-timer.C:
		case <-stop:
			timer.Stop()
			return
		}
	}
}
