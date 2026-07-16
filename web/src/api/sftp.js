import api from './index'
import { apiUrl } from '../utils/apiBase'
import { fetchWithAuth } from './fetchWithAuth'
import { consumeNDJSON } from '../utils/ndjsonStream'

export const listFiles = async (hostId, path = '.', options = {}) => {
    return await api.get(`/sftp/list/${hostId}`, {
        params: { path },
        signal: options.signal,
    })
}

export const getPathBookmarks = async (hostId) => {
    return await api.get(`/sftp/bookmarks/${hostId}`)
}

export const savePathBookmarks = async (hostId, bookmarks) => {
    return await api.put(`/sftp/bookmarks/${hostId}`, {
        history: bookmarks?.history || [],
        favorites: bookmarks?.favorites || [],
    })
}

export const startNativeDownload = async (hostId, path, downloadName) => {
    const { ticket } = await api.post(`/sftp/download-ticket/${hostId}`, null, {
        params: { path },
    })
    if (!ticket) throw new Error('Download ticket was not returned')

    const params = new URLSearchParams({ path, ticket })
    const link = document.createElement('a')
    link.href = apiUrl(`/sftp/native-download/${hostId}?${params.toString()}`)
    link.download = downloadName || ''
    link.style.display = 'none'
    document.body.appendChild(link)
    link.click()
    link.remove()
}

// Text editing intentionally loads the file into memory. Callers must enforce
// an editor-specific size limit before using this API.
export const downloadFileForEditor = async (hostId, path, options = {}) => {
    return await api.get(`/sftp/download/${hostId}`, {
        params: { path, _t: Date.now() },
        headers: { 'X-Termiscope-Editor': '1' },
        responseType: 'blob',
        timeout: 0,
        signal: options.signal,
    })
}

const resolveUploadBlob = (file) => {
    if (!file) return null
    if (file instanceof Blob) return file
    if (file.originFileObj instanceof Blob) return file.originFileObj
    return null
}

export const uploadFile = async (hostId, path, file, onProgress, signal, options = {}) => {
    const blob = resolveUploadBlob(file)
    if (!blob) {
        throw new Error('Invalid file')
    }

    const uploadId = `upload_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
    const fileName = options.fileName || blob.name || file?.name || 'upload'
    
    const formData = new FormData()
    formData.append('path', path)
    formData.append('file_size', String(blob.size ?? 0))
    formData.append('upload_id', uploadId)
    formData.append('overwrite', String(!!options.overwrite))
    formData.append('file', blob, fileName)

    let pollInterval = null
    let pollInFlight = false
    
    if (onProgress) {
        pollInterval = setInterval(async () => {
            if (pollInFlight) return
            pollInFlight = true
            try {
                const res = await fetchWithAuth(apiUrl(`/sftp/upload-progress/${uploadId}`))
                    .then((r) => r.json())
                    .then((body) => (body?.success ? body.data : body))
                if (res && res.status !== 'not_found') {
                    onProgress({
                        type: 'progress',
                        percent: res.percent,
                        speed: res.speed,
                        written: res.written,
                        total: res.total
                    })
                }
            } catch (err) {
                // Ignore polling errors
            } finally {
                pollInFlight = false
            }
        }, 1000)
    }

    try {
        const response = await fetchWithAuth(apiUrl(`/sftp/upload/${hostId}`), {
            method: 'POST',
            body: formData,
            signal
        })

        if (!response.ok) {
            let errorMsg = 'Upload failed'
            try {
                const data = await response.json()
                errorMsg = data.error || errorMsg
            } catch (e) { }
            throw new Error(errorMsg)
        }
        
        if (onProgress) {
            onProgress({ type: 'complete', percent: 100 })
        }
        
        return await response.json()
    } finally {
        if (pollInterval) {
            clearInterval(pollInterval)
        }
    }
}


export const deleteFile = async (hostId, path) => {
    return await api.delete(`/sftp/delete/${hostId}`, { params: { path } })
}

export const renameFile = async (hostId, oldPath, newPath) => {
    return await api.post(`/sftp/rename/${hostId}`, { old_path: oldPath, new_path: newPath })
}

export const pasteFile = async (hostId, source, dest, type, options = {}) => {
    return await api.post(`/sftp/paste/${hostId}`, {
        source,
        dest,
        type,
        dest_file_name: options.destFileName || '',
        overwrite: !!options.overwrite,
    })
}

export const createDirectory = async (hostId, path) => {
    return await api.post(`/sftp/mkdir/${hostId}`, { path })
}

export const createFile = async (hostId, path) => {
    return await api.post(`/sftp/create/${hostId}`, { path })
}

export const isRequestAborted = (error) =>
    error?.code === 'ERR_CANCELED' ||
    error?.name === 'AbortError' ||
    error?.name === 'CanceledError' ||
    error?.message === 'canceled'

export const transferFile = async (sourceHostId, destHostId, sourcePath, destPath, onProgress, type = 'copy', options = {}) => {
    const payload = {
        source_host_id: String(sourceHostId),
        dest_host_id: String(destHostId),
        source_path: sourcePath,
        dest_path: destPath,
        type: type,
    }
    if (options.destFileName != null && options.destFileName !== '') {
        payload.dest_file_name = options.destFileName
    }
    payload.overwrite = !!options.overwrite
    const response = await fetchWithAuth(apiUrl('/sftp/transfer'), {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
        signal: options.signal,
    })

    if (!response.ok) {
        let errorMsg = 'Transfer failed'
        try {
            const data = await response.json()
            errorMsg = data.error || errorMsg
        } catch (e) { }
        throw new Error(errorMsg)
    }

    let lastError = null
    let gotComplete = false
    await consumeNDJSON(response.body, {
        signal: options.signal,
        onEvent: (event) => {
            if (event.type === 'error') lastError = event.message
            if (event.type === 'complete') gotComplete = true
            onProgress?.(event)
        },
        onInvalidLine: (line, error) => console.error('JSON parse error:', error, 'line:', line),
    })

    if (lastError) {
        throw new Error(lastError)
    }
    if (!gotComplete) {
        throw new Error('Transfer incomplete')
    }
}

export const getDirSize = async (hostId, path, options = {}) => {
    try {
        return await api.get(`/sftp/size/${hostId}`, {
            params: { path },
            timeout: 10000, // 10s timeout to prevent long hanging
            _silentError: true, // 静默错误，不在全局拦截器中显示 toast
            signal: options.signal,
        })
    } catch (error) {
        if (isRequestAborted(error)) {
            throw error
        }
        console.warn(`Failed to get dir size for ${path}:`, error.message)
        return null
    }
}

export const getDirSizes = async (hostId, paths, options = {}) => {
    try {
        return await api.post(`/sftp/sizes/${hostId}`, {
            paths: Array.isArray(paths) ? paths : [paths],
        }, {
            timeout: 20000,
            _silentError: true,
            signal: options.signal,
        })
    } catch (error) {
        if (isRequestAborted(error)) {
            throw error
        }
        console.warn('Failed to get dir sizes:', error.message)
        return null
    }
}
