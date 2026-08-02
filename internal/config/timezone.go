package config

import (
	"fmt"
	"sync/atomic"
	"time"
)

var configuredLocation atomic.Pointer[time.Location]

func init() {
	configuredLocation.Store(time.Local)
}

// SetLocation validates and atomically updates the application timezone.
func SetLocation(name string) error {
	if name == "" || name == "Local" {
		configuredLocation.Store(time.Local)
		return nil
	}
	location, err := time.LoadLocation(name)
	if err != nil {
		return fmt.Errorf("invalid timezone %q: %w", name, err)
	}
	configuredLocation.Store(location)
	return nil
}

func Location() *time.Location {
	return configuredLocation.Load()
}
