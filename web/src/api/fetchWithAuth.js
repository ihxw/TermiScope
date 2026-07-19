import authSession from './authSession'

export const fetchWithAuth = (url, options = {}) => authSession.request(url, options)
