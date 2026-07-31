import test from 'node:test'
import assert from 'node:assert/strict'
import { resolveRelativePath, listAncestorPaths } from './sftpPath.js'

test('SFTP relative path resolves dot segments without escaping an absolute root', () => {
	assert.equal(resolveRelativePath('../logs', '/home/user'), '/home/logs')
	assert.equal(resolveRelativePath('../../../etc', '/home/user'), '/etc')
})

test('SFTP relative ancestors stay relative', () => {
	assert.deepEqual(listAncestorPaths('home/user'), ['home', 'home/user'])
})
