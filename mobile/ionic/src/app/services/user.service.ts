import { Injectable } from '@angular/core';
import { ApiService } from './api.service';

@Injectable({
    providedIn: 'root'
})
export class UserService {

    constructor(private api: ApiService) { }

    // Profile / Auth
    getCurrentUser() {
        return this.api.get('/auth/me');
    }

    changePassword(data: any) {
        return this.api.post('/auth/change-password', data);
    }

    setup2FA() {
        return this.api.post<{ secret: string, qr_code: string, otpauth_url: string }>('/auth/2fa/setup');
    }

    verifySetup2FA(token: string, secret: string) {
        return this.api.post('/auth/2fa/verify-setup', { token, secret });
    }

    disable2FA(password: string) {
        return this.api.post('/auth/2fa/disable', { password });
    }

    // Admin User Management
    getUsers() {
        return this.api.get<any[]>('/users');
    }

    createUser(user: any) {
        return this.api.post('/users', user);
    }

    updateUser(id: number | string, user: any) {
        return this.api.put(`/users/${id}`, user);
    }

    deleteUser(id: number | string) {
        return this.api.delete(`/users/${id}`);
    }

    // System
    getSystemSettings() {
        return this.api.get('/system/settings');
    }

    updateSystemSettings(settings: any) {
        return this.api.put('/system/settings', settings);
    }

    backupSystem() {
        return this.api.get('/system/backup', {}, { responseType: 'blob' });
    }

    restoreSystem(file: File) {
        const formData = new FormData();
        formData.append('file', file);
        return this.api.post('/system/restore', formData, {
            headers: { 'Content-Type': 'multipart/form-data' }
        });
    }

    getAgentVersion() {
        return this.api.get('/system/agent-version');
    }
}
