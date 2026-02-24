import api from './index'

export const listFiles = async (hostId, path = '.') => {
    return await api.get(`/sftp/list/${hostId}`, { params: { path } })
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

export const uploadFile = async (hostId, path, file, onProgress) => {
    const formData = new FormData()
    formData.append('path', path)
    formData.append('file', file)
    return await api.post(`/sftp/upload/${hostId}`, formData, {
        headers: {
            'Content-Type': 'multipart/form-data'
        },
        timeout: 0,
        onUploadProgress: (progressEvent) => {
            if (onProgress) {
                const percentCompleted = Math.round((progressEvent.loaded * 100) / progressEvent.total)
                onProgress(percentCompleted)
            }
        }
    })
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

export const getDirSize = async (hostId, path) => {
    try {
        return await api.get(`/sftp/size/${hostId}`, {
            params: { path },
            timeout: 10000, // 10s timeout to prevent long hanging
            _silentError: true // 静默错误，不在全局拦截器中显示 toast
        })
    } catch (error) {
        // 静默失败，不显示toast
        // 返回一个特殊对象表示超时/失败
        console.warn(`Failed to get dir size for ${path}:`, error.message)
        return null
    }
}
