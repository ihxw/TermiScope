import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';

@Injectable({
  providedIn: 'root'
})
export class SystemService {
  constructor(private api: ApiService) {}

  // System Settings - 合并在同一个 /system/settings 端点
  // Web 端: GET /system/settings 获取所有设置（含通知）
  getSettings(): Observable<any> {
    return this.api.get('/system/settings');
  }

  // Web 端: PUT /system/settings 保存（不是 POST）
  saveSettings(settings: any): Observable<any> {
    return this.api.put('/system/settings', settings);
  }

  // Test notifications - 与 Web 端一致
  testEmail(settings: any): Observable<any> {
    return this.api.post('/system/settings/test-email', settings);
  }

  testTelegram(settings: any): Observable<any> {
    return this.api.post('/system/settings/test-telegram', settings);
  }

  // Backup - Web 端: POST /system/backup 返回 JSON { filename, ticket }
  backupDatabase(password?: string): Observable<any> {
    return this.api.post('/system/backup', { password: password || '' });
  }

  // Download backup - Web 端: GET /system/backup/download?file=...&token=...
  getBackupDownloadUrl(filename: string, ticket: string): string {
    const serverUrl = this.api.getServerUrl();
    return `${serverUrl}/api/system/backup/download?file=${filename}&token=${ticket}`;
  }

  // Restore - 与 Web 端一致
  restoreDatabase(file: File, password?: string): Observable<any> {
    const formData = new FormData();
    formData.append('file', file);
    if (password) {
      formData.append('password', password);
    }
    return this.api.post('/system/restore', formData);
  }

  // Agent Version - 与 Web 端一致
  getAgentVersion(): Observable<{ version: string; download_url?: string }> {
    return this.api.get('/system/agent-version');
  }
}
