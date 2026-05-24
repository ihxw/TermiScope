import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import { LoginResponse, User, SystemInfo, UpdateInfo, UpdateStatus } from '../models';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  constructor(private api: ApiService) {}

  login(username: string, password: string, remember: boolean = false): Observable<LoginResponse> {
    return this.api.post<LoginResponse>('/auth/login', { username, password, remember });
  }

  checkInit(): Observable<{ initialized: boolean }> {
    return this.api.get<{ initialized: boolean }>('/auth/check-init');
  }

  initialize(username: string, password: string): Observable<LoginResponse> {
    return this.api.post<LoginResponse>('/auth/initialize', { username, password });
  }

  forgotPassword(email: string): Observable<any> {
    return this.api.post('/auth/forgot-password', { email });
  }

  // Web 端使用 params 传参
  getLoginHistory(page: number = 1, pageSize: number = 10): Observable<any> {
    return this.api.get(`/auth/login-history?page=${page}&page_size=${pageSize}`);
  }

  revokeSession(jti: string): Observable<any> {
    return this.api.post('/auth/sessions/revoke', { jti });
  }

  logout(): Observable<any> {
    return this.api.post('/auth/logout');
  }

  getCurrentUser(): Observable<User> {
    return this.api.get<User>('/auth/me');
  }

  getWSTicket(): Observable<{ ticket: string }> {
    return this.api.post<{ ticket: string }>('/auth/ws-ticket');
  }

  changePassword(currentPassword: string, newPassword: string): Observable<any> {
    return this.api.post('/auth/change-password', { 
      current_password: currentPassword, 
      new_password: newPassword 
    });
  }

  refreshToken(token: string): Observable<LoginResponse> {
    return this.api.post<LoginResponse>('/auth/refresh', { refresh_token: token });
  }

  verify2FALogin(userId: number, code: string, token: string): Observable<LoginResponse> {
    return this.api.post<LoginResponse>('/auth/verify-2fa-login', { 
      user_id: userId, 
      code, 
      token 
    });
  }

  // Reset password - Web 端: POST /auth/reset-password { token, password }
  resetPassword(token: string, password: string): Observable<any> {
    return this.api.post('/auth/reset-password', { token, password });
  }

  getSystemInfo(): Observable<SystemInfo> {
    return this.api.get<SystemInfo>('/system/info');
  }

  // Web 端: POST /system/check-update (不是 GET /system/update/check)
  checkUpdate(): Observable<UpdateInfo> {
    return this.api.post<UpdateInfo>('/system/check-update', {});
  }

  // Web 端: POST /system/upgrade (不是 POST /system/update)
  performUpdate(downloadUrl: string): Observable<any> {
    return this.api.post('/system/upgrade', { download_url: downloadUrl });
  }

  // Web 端: GET /system/update-status (不是 GET /system/update/status)
  getUpdateStatus(): Observable<UpdateStatus> {
    return this.api.get<UpdateStatus>('/system/update-status');
  }
}
