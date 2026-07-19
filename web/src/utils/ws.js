/** WebSocket URL on the same host/port as the page (dev: proxied by Vite on :5173). */
export function buildWebSocketUrl(pathWithQuery) {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  const path = pathWithQuery.startsWith('/') ? pathWithQuery : `/${pathWithQuery}`
  return `${protocol}//${window.location.host}${path}`
}
