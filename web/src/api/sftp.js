import api from './index'
import { apiUrl } from '../utils/apiBase'

export const listFiles = async (hostId, path = '.', options = {}) => {
    return await api.get(`/sftp/list/${hostId}`, {
        params: { path },
        signal: options.signal,
    })
}

export const downloadFile = async (hostId, path, onProgress) => {
    return await api.get(`/sftp/download/${hostId}`, {
        params: { path, _t: Date.now() },
        responseType: 'blob',
        timeout: 0,
        onDownloadProgress: (progressEvent) => {
            if (onProgress) {
                const percentCompleted = Math.round((progressEvent.loaded * 100) / progressEvent.total)
                onProgress(percentCompleted)
            }
        }
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

    const token = localStorage.getItem('token')
    const uploadId = `upload_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
    const fileName = options.fileName || blob.name || file?.name || 'upload'
    
    const formData = new FormData()
    formData.append('path', path)
    formData.append('file_size', String(blob.size ?? 0))
    formData.append('upload_id', uploadId)
    formData.append('file', blob, fileName)

    let pollInterval = null
    
    if (onProgress) {
        pollInterval = setInterval(async () => {
            try {
                const res = await fetch(apiUrl(`/sftp/upload-progress/${uploadId}`), {
                    headers: { Authorization: `Bearer ${token}` },
                }).then((r) => r.json()).then((body) => (body?.success ? body.data : body))
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
            }
        }, 500)
    }

    try {
        const response = await fetch(apiUrl(`/sftp/upload/${hostId}`), {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`
            },
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

export const pasteFile = async (hostId, source, dest, type) => {
    return await api.post(`/sftp/paste/${hostId}`, { source, dest, type })
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
    const token = localStorage.getItem('token')
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
    const response = await fetch(apiUrl('/sftp/transfer'), {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
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

    const reader = response.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''
    let lastError = null
    let gotComplete = false

    while (true) {
        if (options.signal?.aborted) {
            await reader.cancel().catch(() => {})
            throw new DOMException('Aborted', 'AbortError')
        }
        const { done, value } = await reader.read()
        if (done) break
        
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop()

        for (const line of lines) {
            if (line.trim()) {
                try {
                    const event = JSON.parse(line)
                    console.log('📥 Received event:', event.type, event)
                    if (event.type === 'error') {
                        lastError = event.message
                    }
                    if (event.type === 'complete') {
                        gotComplete = true
                    }
                    if (onProgress) onProgress(event)
                } catch (e) {
                    console.error('JSON parse error:', e, 'line:', line)
                }
            }
        }
    }

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
