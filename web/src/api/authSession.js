const memoryValues = new Map()
const defaultStorage = {
  getItem: (key) => memoryValues.get(key) ?? null,
  setItem: (key, value) => memoryValues.set(key, String(value)),
  removeItem: (key) => memoryValues.delete(key),
}

// 清理旧版本遗留的持久化访问令牌；会话通过 HttpOnly refresh cookie 恢复。
globalThis.localStorage?.removeItem('token')

const cookieValue = (cookies, name) => {
  const prefix = `${name}=`
  return String(cookies || '')
    .split(';')
    .map((cookie) => cookie.trim())
    .find((cookie) => cookie.startsWith(prefix))
    ?.slice(prefix.length) || ''
}

export const createAuthSession = ({
  storage = defaultStorage,
  readCookies = () => globalThis.document?.cookie || '',
  fetchImpl = (...args) => globalThis.fetch(...args),
  refreshUrl = '/api/auth/refresh',
} = {}) => {
  let refreshFlight = null

  const getAccessToken = () => storage.getItem('token')

  const setAccessToken = (token) => {
    if (token) storage.setItem('token', token)
    else storage.removeItem('token')
  }

  const withAuthHeaders = (headers = {}) => {
    const next = new Headers(headers)
    const token = getAccessToken()
    if (token && !next.has('Authorization')) {
      next.set('Authorization', `Bearer ${token}`)
    }
    const csrfToken = cookieValue(readCookies(), 'csrf_token')
    if (csrfToken && !next.has('X-CSRF-Token')) {
      next.set('X-CSRF-Token', csrfToken)
    }
    return next
  }

  const refreshAccessToken = () => {
    if (!refreshFlight) {
      refreshFlight = fetchImpl(refreshUrl, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      })
        .then(async (response) => {
          if (!response.ok) throw new Error('Session refresh failed')
          const body = await response.json()
          const token = body?.data?.token
          if (!body?.success || !token) throw new Error('Session refresh failed')
          setAccessToken(token)
          return token
        })
        .finally(() => {
          refreshFlight = null
        })
    }
    return refreshFlight
  }

  const request = async (url, options = {}) => {
    const requestOptions = {
      ...options,
      credentials: options.credentials || 'include',
      headers: withAuthHeaders(options.headers),
    }
    let response = await fetchImpl(url, requestOptions)
    if (response.status !== 401 || options.skipAuthRefresh) return response

    await refreshAccessToken()
	const refreshedToken = getAccessToken()
	const retryHeaders = withAuthHeaders(options.headers)
	if (refreshedToken) retryHeaders.set('Authorization', `Bearer ${refreshedToken}`)
    response = await fetchImpl(url, {
      ...requestOptions,
      headers: retryHeaders,
    })
    return response
  }

  return {
    getAccessToken,
    setAccessToken,
    clearAccessToken: () => setAccessToken(null),
    getCsrfToken: () => cookieValue(readCookies(), 'csrf_token'),
    withAuthHeaders,
    refreshAccessToken,
    request,
  }
}

const authSession = createAuthSession()

export default authSession
