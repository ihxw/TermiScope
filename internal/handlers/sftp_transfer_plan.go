package handlers

type remoteTransferAdapters struct {
	agentDirect func() bool
	agentRelay  func() bool
	directRsync func() bool
	serverSCP   func() bool
	relay       func() error
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
