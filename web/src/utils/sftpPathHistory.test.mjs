import test from 'node:test'
import assert from 'node:assert/strict'
import { createSftpPathHistory } from './sftpPathHistory.js'

test('SFTP path history truncates forward entries after new navigation', () => {
  const history = createSftpPathHistory('/home')
  history.commit('/home/logs')
  history.commit('/var')
  assert.equal(history.back(), '/home/logs')

  history.commit('/tmp')

  assert.deepEqual(history.snapshot(), {
    entries: ['/home', '/home/logs', '/tmp'],
    index: 2,
    canGoBack: true,
    canGoForward: false,
  })
})
