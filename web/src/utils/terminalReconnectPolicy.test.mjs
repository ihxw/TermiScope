import test from 'node:test'
import assert from 'node:assert/strict'
import {
  TERMINAL_IDLE_TIMEOUT_CLOSE_CODE,
  isTerminalIdleTimeoutClose,
  shouldAutoReconnectTerminalClose,
} from './terminalReconnectPolicy.js'

test('terminal reconnect policy only auto-reconnects idle timeout closes', () => {
  assert.equal(
    shouldAutoReconnectTerminalClose({ code: TERMINAL_IDLE_TIMEOUT_CLOSE_CODE, reason: 'idle timeout' }),
    true,
  )
  assert.equal(
    shouldAutoReconnectTerminalClose({ code: 1006, reason: '' }),
    false,
  )
  assert.equal(
    shouldAutoReconnectTerminalClose({ code: 1011, reason: 'SSH connection failed' }),
    false,
  )
  assert.equal(
    shouldAutoReconnectTerminalClose({ code: 1000, reason: 'session closed' }),
    false,
  )
})

test('terminal reconnect policy respects explicit stop and error state', () => {
  const idleTimeoutClose = { code: TERMINAL_IDLE_TIMEOUT_CLOSE_CODE, reason: 'idle timeout' }

  assert.equal(shouldAutoReconnectTerminalClose(idleTimeoutClose, { manualDisconnected: true }), false)
  assert.equal(shouldAutoReconnectTerminalClose(idleTimeoutClose, { sessionEnded: true }), false)
  assert.equal(shouldAutoReconnectTerminalClose(idleTimeoutClose, { connectionErrorSeen: true }), false)
})

test('terminal idle timeout close can be recognized by code or reason', () => {
  assert.equal(isTerminalIdleTimeoutClose({ code: TERMINAL_IDLE_TIMEOUT_CLOSE_CODE, reason: '' }), true)
  assert.equal(isTerminalIdleTimeoutClose({ code: 1000, reason: 'idle timeout' }), true)
  assert.equal(isTerminalIdleTimeoutClose({ code: 1000, reason: 'session closed' }), false)
})
