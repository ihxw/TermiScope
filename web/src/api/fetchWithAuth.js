import { apiUrl } from '../utils/apiBase'

let refreshing = null

const getCookie = (name) => {
  const prefix = `${name}=`
  return document.cookie
    .split(';')
    .map((cookie) => cookie.trim())
    .find((cookie) => cookie.startsWith(prefix))
    ?.slice(prefix.length) || ''
}

const authHeaders = (headers = {}) => {
  const next = new Headers(headers)
  const token = localStorage.getItem('token')
  if (token && !next.has('Authorization')) {
    next.set('Authorization', `Bearer ${token}`)
  }
  const csrfToken = getCookie('csrf_token')
  if (csrfToken && !next.has('X-CSRF-Token')) {
    next.set('X-CSRF-Token', csrfToken)
  }
  return next
}

const refreshAccessToken = async () => {
  if (!refreshing) {
    refreshing = fetch(apiUrl('/auth/refresh'), {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
    })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error('Session refresh failed')
        }
        const body = await response.json()
        const token = body?.data?.token
        if (!body?.success || !token) {
          throw new Error('Session refresh failed')
        }
        localStorage.setItem('token', token)
        return token
      })
      .finally(() => {
        refreshing = null
      })
  }
  return refreshing
}

export const fetchWithAuth = async (url, options = {}) => {
  const request = {
    ...options,
    credentials: options.credentials || 'include',
    headers: authHeaders(options.headers),
  }

  let response = await fetch(url, request)
  if (response.status !== 401 || options.skipAuthRefresh) {
    return response
  }

  await refreshAccessToken()
  response = await fetch(url, {
    ...request,
    headers: authHeaders(options.headers),
  })
  return response
}
