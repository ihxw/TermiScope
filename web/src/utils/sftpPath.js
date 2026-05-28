const trimTrailingSlash = (path) => {
  const trimmed = path.replace(/\/+$/, '')
  return trimmed || (path.startsWith('/') ? '/' : '')
}

/** Normalize free-form path input before navigation or completion. */
export function normalizeRemotePathInput(input, fallback = '') {
  const trimmed = (input || '').trim()
  if (!trimmed) return fallback
  const collapsed = trimmed.replace(/\/+/g, '/')
  if (collapsed === '/') return '/'
  return trimTrailingSlash(collapsed) || fallback
}

/** Build a remote path from directory cwd and entry name (matches SftpBrowser conventions). */
export function buildRemotePath(cwd, name) {
  if (!name) return cwd || '.'
  const dir = trimTrailingSlash(cwd || '.') || '.'
  if (dir === '.' || dir === '') {
    return name
  }
  if (dir === '/') {
    return `/${name}`
  }
  return `${dir}/${name}`
}

/** Resolve a relative path segment against cwd (for path completion). */
export function resolveRelativePath(segment, cwd = '.') {
  const part = trimTrailingSlash(segment || '')
  if (!part || part === '.') return cwd || '.'
  if (part.startsWith('/')) return part || '/'
  const base = trimTrailingSlash(cwd || '.') || '.'
  if (base === '.' || base === '') return part
  if (base === '/') return `/${part}`
  return `${base}/${part}`
}

/**
 * Split a typed path into parent directory + final segment prefix for autocomplete.
 * @returns {{ parent: string, prefix: string, isAbsolute: boolean }}
 */
export function splitPathForCompletion(input, cwd = '.') {
  const trimmed = (input || '').trim().replace(/\/+/g, '/')
  if (!trimmed) {
    return { parent: cwd || '.', prefix: '', isAbsolute: false }
  }

  const isAbsolute = trimmed.startsWith('/')
  if (trimmed.endsWith('/')) {
    const stripped = trimmed.replace(/\/+$/, '')
    if (stripped === '') {
      return { parent: '/', prefix: '', isAbsolute: true }
    }
    const parent = isAbsolute ? stripped : resolveRelativePath(stripped, cwd)
    return { parent, prefix: '', isAbsolute }
  }

  const lastSlash = trimmed.lastIndexOf('/')
  if (lastSlash === -1) {
    const parent = isAbsolute ? '/' : (cwd || '.')
    return { parent, prefix: trimmed, isAbsolute }
  }

  const parentPart = trimmed.slice(0, lastSlash)
  const prefix = trimmed.slice(lastSlash + 1)
  if (isAbsolute) {
    const parent = parentPart === '' ? '/' : parentPart
    return { parent, prefix, isAbsolute }
  }
  const parent = resolveRelativePath(parentPart, cwd)
  return { parent, prefix, isAbsolute }
}

/** Ancestor paths of cwd (including cwd), for static completion suggestions. */
export function listAncestorPaths(cwd) {
  if (!cwd || cwd === '.') return ['.']
  const normalized = trimTrailingSlash(cwd) || '/'
  if (normalized === '/') return ['/']
  const parts = normalized.split('/').filter(Boolean)
  const isAbs = normalized.startsWith('/')
  const out = []
  let acc = isAbs ? '' : ''
  for (let i = 0; i < parts.length; i++) {
    acc = acc === '' && isAbs ? `/${parts[i]}` : `${acc}/${parts[i]}`
    out.push(acc)
  }
  if (isAbs && !out.includes('/')) out.unshift('/')
  return out
}
