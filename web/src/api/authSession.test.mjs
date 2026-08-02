import test from 'node:test'
import assert from 'node:assert/strict'
import { createAuthSession } from './authSession.js'

const createStorage = (initial = {}) => {
  const values = new Map(Object.entries(initial))
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  }
}

test('concurrent refresh calls share one request and store the new token', async () => {
  const storage = createStorage({ token: 'old-token' })
  let refreshCalls = 0
  let releaseRefresh
  const refreshPending = new Promise((resolve) => { releaseRefresh = resolve })
  const session = createAuthSession({
    storage,
    readCookies: () => '',
    fetchImpl: async () => {
      refreshCalls += 1
      await refreshPending
      return new Response(JSON.stringify({ success: true, data: { token: 'new-token' } }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    },
  })

  const first = session.refreshAccessToken()
  const second = session.refreshAccessToken()
  releaseRefresh()

  assert.equal(await first, 'new-token')
  assert.equal(await second, 'new-token')
  assert.equal(refreshCalls, 1)
  assert.equal(storage.getItem('token'), 'new-token')
})

test('auth headers use the latest token and CSRF cookie without replacing explicit headers', () => {
  const storage = createStorage({ token: 'new-token' })
  const session = createAuthSession({
    storage,
    readCookies: () => 'theme=dark; csrf_token=csrf-value',
    fetchImpl: async () => { throw new Error('unused') },
  })

  const headers = session.withAuthHeaders({ Accept: 'application/json' })
  assert.equal(headers.get('Authorization'), 'Bearer new-token')
  assert.equal(headers.get('X-CSRF-Token'), 'csrf-value')
  assert.equal(headers.get('Accept'), 'application/json')

  const explicit = session.withAuthHeaders({ Authorization: 'Bearer explicit' })
  assert.equal(explicit.get('Authorization'), 'Bearer explicit')
})

test('refresh retry replaces an expired explicit authorization header', async () => {
	const storage = createStorage({ token: 'expired-token' })
	const seen = []
	const session = createAuthSession({
		storage,
		readCookies: () => '',
		fetchImpl: async (url, options) => {
			if (url === '/api/auth/refresh') {
				return new Response(JSON.stringify({ success: true, data: { token: 'fresh-token' } }), {
					status: 200,
					headers: { 'Content-Type': 'application/json' },
				})
			}
			seen.push(options.headers.get('Authorization'))
			return new Response('', { status: seen.length === 1 ? 401 : 200 })
		},
	})

	await session.request('/protected', { headers: { Authorization: 'Bearer expired-token' } })
	assert.deepEqual(seen, ['Bearer expired-token', 'Bearer fresh-token'])
})
