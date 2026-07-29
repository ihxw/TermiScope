import test from 'node:test'
import assert from 'node:assert/strict'
import {
  TERMINAL_LOCAL_INPUT_MODE_RESET_SEQUENCE,
  isTerminalPointerModeReport,
} from './terminalInputModes.js'

test('detects xterm mouse and focus reports emitted by local terminal modes', () => {
  assert.equal(isTerminalPointerModeReport('\x1b[M !!'), true)
  assert.equal(isTerminalPointerModeReport('\x1b[<0;12;8M'), true)
  assert.equal(isTerminalPointerModeReport('\x1b[<0;12;8m'), true)
  assert.equal(isTerminalPointerModeReport('\x1b[35;12;8M'), true)
  assert.equal(isTerminalPointerModeReport('\x1b[I'), true)
  assert.equal(isTerminalPointerModeReport('\x1b[O'), true)
})

test('detects batched pointer mode reports', () => {
  assert.equal(isTerminalPointerModeReport('\x1b[<0;12;8M\x1b[<0;12;8m'), true)
})

test('does not treat keyboard control sequences or mixed input as mouse reports', () => {
  assert.equal(isTerminalPointerModeReport('\x1b[A'), false)
  assert.equal(isTerminalPointerModeReport('\x1b[200~pasted\x1b[201~'), false)
  assert.equal(isTerminalPointerModeReport('ls\r'), false)
  assert.equal(isTerminalPointerModeReport('\x1b[<0;12;8Mls\r'), false)
  assert.equal(isTerminalPointerModeReport('\x1b[M'), false)
})

test('local input mode reset disables stale pointer-related modes', () => {
  for (const mode of ['?9l', '?1000l', '?1002l', '?1003l', '?1005l', '?1006l', '?1015l', '?1004l', '?2004l']) {
    assert.equal(
      TERMINAL_LOCAL_INPUT_MODE_RESET_SEQUENCE.includes(`\x1b[${mode}`),
      true,
      `missing reset sequence for ${mode}`,
    )
  }
})
