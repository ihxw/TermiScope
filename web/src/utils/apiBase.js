/**
 * API base URL. In Vite dev (:5173), large uploads go directly to the Go backend
 * (:3000) to avoid an extra proxy hop that often caps throughput on LAN/Windows.
 */
export function getApiBase() {
  const { protocol, hostname, port } = window.location
  if (port === '5173' || port === '5174') {
    const proto = protocol === 'https:' ? 'https:' : 'http:'
    return `${proto}//${hostname}:3000/api`
  }
  return '/api'
}

/** Full URL for a path under /api (path may start with or without /). */
export function apiUrl(path) {
  const base = getApiBase().replace(/\/$/, '')
  const p = path.startsWith('/') ? path : `/${path}`
  return `${base}${p}`
}
