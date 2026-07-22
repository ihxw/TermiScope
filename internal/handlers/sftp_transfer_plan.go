package handlers

const serverRelayMaxSize int64 = 32 * 1024 * 1024

type remoteTransferAdapters struct {
	agentDirect func() bool
	agentRelay  func() bool
	directRsync func() bool
	serverSCP   func() bool
	relay       func() error
}

// shouldUseServerRelay keeps small transfers off the agent command path, whose
// polling and connection setup can take longer than the transfer itself.
func shouldUseServerRelay(isSymlink bool, totalSize int64) bool {
	return isSymlink || totalSize <= serverRelayMaxSize
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
