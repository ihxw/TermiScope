export const TERMINAL_IDLE_TIMEOUT_CLOSE_CODE = 4000

const isIdleTimeoutClose = (event) => {
  const reason = String(event?.reason || '').trim().toLowerCase()
  return event?.code === TERMINAL_IDLE_TIMEOUT_CLOSE_CODE || reason === 'idle timeout'
}

export const createTerminalSessionState = () => {
  const state = {
    manualDisconnected: false,
    sessionEnded: false,
    connectionErrorSeen: false,
    connectionEstablished: false,
    pendingInputLine: '',
  }

  const snapshot = () => ({ ...state })

  const beginConnect = () => {
    state.manualDisconnected = false
    state.sessionEnded = false
    state.connectionErrorSeen = false
    state.connectionEstablished = false
    state.pendingInputLine = ''
  }

  const recordInput = (data) => {
    if (!data) return snapshot()
    if (data === '\x04') {
      state.sessionEnded = true
      state.manualDisconnected = true
      return snapshot()
    }
    if (data.startsWith('\x1b')) return snapshot()

    for (const char of data) {
      if (char === '\x03' || char === '\x15') {
        state.pendingInputLine = ''
      } else if (char === '\r' || char === '\n') {
        const command = state.pendingInputLine.trim()
        if (command === 'exit' || command === 'logout') {
          state.sessionEnded = true
          state.manualDisconnected = true
        }
        state.pendingInputLine = ''
      } else if (char === '\u007f' || char === '\b') {
        state.pendingInputLine = state.pendingInputLine.slice(0, -1)
      } else if (char >= ' ' && char !== '\x7f') {
        state.pendingInputLine += char
      }
    }
    return snapshot()
  }

  const closed = (event) => {
    const unexpectedlyClosed = event?.code !== 1000 && event?.code !== 1005
    const shouldReconnect = (isIdleTimeoutClose(event)
      || (state.connectionEstablished && unexpectedlyClosed))
      && !state.manualDisconnected
      && !state.sessionEnded
      && !state.connectionErrorSeen
    const endedQuietly = state.manualDisconnected
      || state.sessionEnded
      || event?.code === 1000
      || event?.code === 1005
    return { shouldReconnect, endedQuietly, ...snapshot() }
  }

  return {
    snapshot,
    beginConnect,
    connected: () => {
      state.connectionErrorSeen = false
      state.connectionEstablished = true
    },
    markError: () => { state.connectionErrorSeen = true },
    recordInput,
    closed,
    canReconnect: (connectionStatus) => !state.manualDisconnected
      && !state.sessionEnded
      && connectionStatus === 'Disconnected',
    manualDisconnect: () => {
      state.manualDisconnected = true
      state.sessionEnded = true
    },
    dispose: () => {
      state.manualDisconnected = true
      state.sessionEnded = true
      state.connectionErrorSeen = false
      state.pendingInputLine = ''
    },
  }
}
