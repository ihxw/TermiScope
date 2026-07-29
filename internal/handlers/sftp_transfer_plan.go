package handlers

const serverRelayMaxSize int64 = 32 * 1024 * 1024

type remoteTransferAdapters struct {
	agentDirect func() bool
	agentRelay  func() bool
	directRsync func() bool
	serverSCP   func() bool
	relay       func() error
}

// shouldUseServerRelay keeps the legacy automatic heuristic available for
// callers that explicitly request auto mode.
func shouldUseServerRelay(isSymlink bool, totalSize int64) bool {
	return isSymlink || totalSize <= serverRelayMaxSize
}

// transferRequiresRelay resolves the requested transfer method into whether
// the planner must skip direct/agent transports and use server relay.
func transferRequiresRelay(method string, isSymlink bool, totalSize int64) bool {
	if isSymlink {
		return true
	}
	switch method {
	case "relay":
		return true
	case "auto":
		return shouldUseServerRelay(isSymlink, totalSize)
	case "agent", "":
		return false
	default:
		return false
	}
}

// executeRemoteTransfer owns transfer fallback ordering. The concrete SSH,
// process, and SFTP implementations remain adapters supplied by the caller.
func executeRemoteTransfer(requiresRelay bool, adapters remoteTransferAdapters) error {
	if !requiresRelay {
		if adapters.agentDirect() {
			return nil
		}
		if adapters.agentRelay() {
			return nil
		}
		if adapters.directRsync() {
			return nil
		}
		if adapters.serverSCP() {
			return nil
		}
	}
	return adapters.relay()
}
