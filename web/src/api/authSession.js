const defaultStorage = {
  getItem: (key) => globalThis.localStorage?.getItem(key) ?? null,
  setItem: (key, value) => globalThis.localStorage?.setItem(key, value),
  removeItem: (key) => globalThis.localStorage?.removeItem(key),
}

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
    response = await fetchImpl(url, {
      ...requestOptions,
      headers: withAuthHeaders(options.headers),
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
