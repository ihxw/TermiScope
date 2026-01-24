import api from './index'

export const listCommandTemplates = async () => {
    return await api.get('/command-templates')
}

export const createCommandTemplate = async (data) => {
    return await api.post('/command-templates', data)
}

export const updateCommandTemplate = async (id, data) => {
    return await api.put(`/command-templates/${id}`, data)
}

export const deleteCommandTemplate = async (id) => {
    return await api.delete(`/command-templates/${id}`)
}
