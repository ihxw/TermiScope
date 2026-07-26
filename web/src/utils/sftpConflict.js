/** Check if a filename already exists in a directory listing */
export function hasNameConflict(files, name) {
  if (!name || !Array.isArray(files)) return false
  return files.some((f) => f.name === name)
}

/** Generate a non-conflicting name like "file (1).txt" */
export function generateKeepBothName(files, name) {
  const dot = name.lastIndexOf('.')
  const base = dot > 0 ? name.slice(0, dot) : name
  const ext = dot > 0 ? name.slice(dot) : ''
  let n = 1
  let candidate = `${base} (${n})${ext}`
  while (hasNameConflict(files, candidate)) {
    n += 1
    candidate = `${base} (${n})${ext}`
  }
  return candidate
}
