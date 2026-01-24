import api from './index'

export const listFiles = async (hostId, path = '.') => {
    return await api.get(`/sftp/list/${hostId}`, { params: { path } })
}

export const downloadFile = async (hostId, path, onProgress) => {
    const token = localStorage.getItem('token')
    return await api.get(`/sftp/download/${hostId}`, {
        params: { path, token },
        responseType: 'blob',
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
