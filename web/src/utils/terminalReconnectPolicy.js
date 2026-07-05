export const TERMINAL_IDLE_TIMEOUT_CLOSE_CODE = 4000

export const isTerminalIdleTimeoutClose = (event) => {
  const reason = String(event?.reason || '').trim().toLowerCase()
  return event?.code === TERMINAL_IDLE_TIMEOUT_CLOSE_CODE || reason === 'idle timeout'
}

export const shouldAutoReconnectTerminalClose = (event, state = {}) => {
  const {
    manualDisconnected = false,
    sessionEnded = false,
    connectionErrorSeen = false,
  } = state

  if (manualDisconnected || sessionEnded || connectionErrorSeen) {
    return false
  }

  return isTerminalIdleTimeoutClose(event)
}
