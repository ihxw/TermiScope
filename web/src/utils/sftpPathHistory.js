export const createSftpPathHistory = (initialPath) => {
  let entries = initialPath ? [initialPath] : []
  let index = entries.length - 1

  const snapshot = () => ({
    entries: [...entries],
    index,
    canGoBack: index > 0,
    canGoForward: index >= 0 && index < entries.length - 1,
  })

  const commit = (path) => {
    if (!path) return snapshot()
    if (index >= 0 && entries[index] === path) return snapshot()
    if (index < entries.length - 1) entries = entries.slice(0, index + 1)
    entries.push(path)
    index = entries.length - 1
    return snapshot()
  }

  return {
    snapshot,
    commit,
    initialize: (path) => {
      if (entries.length === 0 && path) {
        entries = [path]
        index = 0
      }
      return snapshot()
    },
    reset: () => {
      entries = []
      index = -1
      return snapshot()
    },
    back: () => {
      if (index <= 0) return null
      index -= 1
      return entries[index]
    },
    forward: () => {
      if (index < 0 || index >= entries.length - 1) return null
      index += 1
      return entries[index]
    },
  }
}
