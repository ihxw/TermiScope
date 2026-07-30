package firewall

import (
	"log"
	"runtime"
)

func finalizeStatus(s Status) Status {
	s.Platform = runtime.GOOS
	s.Privileged = isProcessPrivileged()
	if !s.Privileged && s.PrivilegeHint == "" {
		s.PrivilegeHint = defaultPrivilegeHint()
	}
	return s
}

// LogStartupStatus logs firewall availability once at server startup.
func LogStartupStatus() {
	mgr := NewManager()
	st, err := mgr.Status()
	if err != nil {
		log.Printf("Firewall: failed to read status: %v", err)
		return
	}
	if st.Available {
		log.Printf("Firewall: available (backend=%s, platform=%s, enabled=%v)", st.Backend, st.Platform, st.Enabled)
		return
	}
	msg := st.Message
	if msg == "" {
		msg = "unavailable"
	}
	log.Printf("Firewall: unavailable on %s (privileged=%v): %s; hint: %s", st.Platform, st.Privileged, msg, st.PrivilegeHint)
}
