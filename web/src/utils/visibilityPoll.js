/** Run callback on interval only while the document tab is visible. */
export function startVisibilityPoll(callback, intervalMs, options = {}) {
  const { immediate = true } = options
  const tick = () => {
    if (document.visibilityState === 'visible') {
      callback()
    }
  }
  if (immediate) tick()
  const id = setInterval(tick, intervalMs)
  return () => clearInterval(id)
}
