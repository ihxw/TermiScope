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

  setup2FA(): Observable<any> {
    return this.api.post('/auth/2fa/setup', {});
  }

  verify2FASetup(code: string): Observable<any> {
    return this.api.post('/auth/2fa/verify', { code });
  }

  disable2FA(code: string): Observable<any> {
    return this.api.post('/auth/2fa/disable', { code });
  }

  getSystemInfo(): Observable<SystemInfo> {
    return this.api.get<SystemInfo>('/system/info');
  }

  checkUpdate(): Observable<UpdateInfo> {
    return this.api.get<UpdateInfo>('/system/update/check');
  }

  performUpdate(downloadUrl: string): Observable<any> {
    return this.api.post('/system/update', { download_url: downloadUrl });
  }

  getUpdateStatus(): Observable<UpdateStatus> {
    return this.api.get<UpdateStatus>('/system/update/status');
  }
}
