import api from './index'

export const getUsers = async (page = 1, pageSize = 10, search = '') => {
    return await api.get('/users', { params: { page, page_size: pageSize, search } })
}

export const createUser = async (userData) => {
    return await api.post('/users', userData)
}

export const updateUser = async (id, userData) => {
    return await api.put(`/users/${id}`, userData)
}

export const deleteUser = async (id) => {
    return await api.delete(`/users/${id}`)
}
