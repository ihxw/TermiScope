import test from 'node:test'
import assert from 'node:assert/strict'
import { consumeNDJSON } from './ndjsonStream.js'

test('NDJSON stream emits split records and a final record without newline', async () => {
  const encoder = new TextEncoder()
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode('{"type":"pro'))
      controller.enqueue(encoder.encode('gress","percent":50}\n{"type":"complete"}'))
      controller.close()
    },
  })
  const events = []

  await consumeNDJSON(body, { onEvent: (event) => events.push(event) })

  assert.deepEqual(events, [
    { type: 'progress', percent: 50 },
    { type: 'complete' },
  ])
})
