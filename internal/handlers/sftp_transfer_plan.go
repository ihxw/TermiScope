package handlers

type remoteTransferAdapters struct {
	directRsync func() bool
	serverSCP   func() bool
	relay       func() error
}

// executeRemoteTransfer owns transfer fallback ordering. The concrete SSH,
// process, and SFTP implementations remain adapters supplied by the caller.
func executeRemoteTransfer(requiresRelay bool, adapters remoteTransferAdapters) error {
	if !requiresRelay {
		if adapters.directRsync() {
			return nil
		}
		if adapters.serverSCP() {
			return nil
		}
	}
	return adapters.relay()
}
