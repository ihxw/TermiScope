import test from 'node:test'
import assert from 'node:assert/strict'
import { createTerminalSessionState, TERMINAL_IDLE_TIMEOUT_CLOSE_CODE } from './terminalSessionState.js'

test('terminal session does not reconnect after an explicit exit command', () => {
  const session = createTerminalSessionState()
  session.beginConnect()
  session.connected()
  session.recordInput('ex')
  session.recordInput('it\r')

  const close = session.closed({ code: TERMINAL_IDLE_TIMEOUT_CLOSE_CODE, reason: 'idle timeout' })

  assert.equal(close.shouldReconnect, false)
  assert.equal(close.endedQuietly, true)
  assert.equal(session.snapshot().sessionEnded, true)
})

test('terminal session reconnects after an idle timeout without an error', () => {
  const session = createTerminalSessionState()
  session.beginConnect()
  session.connected()

  assert.equal(
    session.closed({ code: TERMINAL_IDLE_TIMEOUT_CLOSE_CODE, reason: 'idle timeout' }).shouldReconnect,
    true,
  )

  session.markError()
  assert.equal(
    session.closed({ code: TERMINAL_IDLE_TIMEOUT_CLOSE_CODE, reason: 'idle timeout' }).shouldReconnect,
    false,
  )
})

test('terminal session reconnects after an established connection closes unexpectedly', () => {
  const session = createTerminalSessionState()
  session.beginConnect()
  session.connected()

  assert.equal(session.closed({ code: 1006, reason: '' }).shouldReconnect, true)
})

test('terminal session does not retry a connection that never opened', () => {
  const session = createTerminalSessionState()
  session.beginConnect()
  session.markError()

  assert.equal(session.closed({ code: 1006, reason: '' }).shouldReconnect, false)
})

test('terminal session does not reconnect after a normal remote close', () => {
  const session = createTerminalSessionState()
  session.beginConnect()
  session.connected()

  assert.equal(session.closed({ code: 1000, reason: 'session closed' }).shouldReconnect, false)
})
