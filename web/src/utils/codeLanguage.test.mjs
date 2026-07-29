import test from 'node:test'
import assert from 'node:assert/strict'
import { detectCodeLanguage } from './codeLanguage.js'

test('detects Monaco languages from file names and extensions', () => {
  assert.equal(detectCodeLanguage('Dockerfile', ''), 'dockerfile')
  assert.equal(detectCodeLanguage('/home/user/.zshrc', ''), 'shell')
  assert.equal(detectCodeLanguage('component.tsx', ''), 'typescript')
  assert.equal(detectCodeLanguage('settings.yaml', ''), 'yaml')
})

test('detects extensionless scripts from shebangs', () => {
  assert.equal(detectCodeLanguage('deploy', '#!/usr/bin/env bash\necho ok'), 'shell')
  assert.equal(detectCodeLanguage('worker', '#!/usr/bin/env python3\nprint("ok")'), 'python')
  assert.equal(detectCodeLanguage('server', '#!/usr/bin/env node\nconsole.log("ok")'), 'javascript')
})

test('detects structured and source content when the extension is unknown', () => {
  assert.equal(detectCodeLanguage('payload.txt', '{"ready":true}'), 'json')
  assert.equal(detectCodeLanguage('query', 'SELECT id, name FROM users;'), 'sql')
  assert.equal(detectCodeLanguage('main', 'package main\n\nfunc main() {}'), 'go')
  assert.equal(detectCodeLanguage('config', 'server:\n  port: 8080\n  debug: true'), 'yaml')
})

test('keeps ordinary text as plaintext', () => {
  assert.equal(detectCodeLanguage('README', 'This is a short deployment note.'), 'plaintext')
})
