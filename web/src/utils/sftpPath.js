/** Build a remote path from directory cwd and entry name (matches SftpBrowser conventions). */
export function buildRemotePath(cwd, name) {
  if (!name) return cwd || '.'
  const dir = (cwd || '.').replace(/\/$/, '') || '.'
  if (dir === '.' || dir === '') {
    return name
  }
  if (dir === '/') {
    return `/${name}`
  }
  return `${dir}/${name}`
}
