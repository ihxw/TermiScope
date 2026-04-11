import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import { SystemSettings, NotificationSettings } from '../models';

@Injectable({
  providedIn: 'root'
})
export class SystemService {
  constructor(private api: ApiService) {}

  // System Settings
  getSettings(): Observable<SystemSettings> {
    return this.api.get<SystemSettings>('/system/settings');
  }

  saveSettings(settings: SystemSettings): Observable<any> {
    return this.api.post('/system/settings', settings);
  }

  // Notification Settings
  getNotificationSettings(): Observable<NotificationSettings> {
    return this.api.get<NotificationSettings>('/system/notification-settings');
  }

  saveNotificationSettings(settings: NotificationSettings): Observable<any> {
    return this.api.post('/system/notification-settings', settings);
  }

  // Test notifications
  testEmail(settings: NotificationSettings): Observable<any> {
    return this.api.post('/system/settings/test-email', settings);
  }

  testTelegram(settings: NotificationSettings): Observable<any> {
    return this.api.post('/system/settings/test-telegram', settings);
  }

  // Backup & Restore
  backupDatabase(password?: string): Observable<Blob> {
    return this.api.post('/system/backup', { password }, { responseType: 'blob' });
  }

  restoreDatabase(file: File, password?: string): Observable<any> {
    const formData = new FormData();
    formData.append('file', file);
    if (password) {
      formData.append('password', password);
    }
    return this.api.post('/system/restore', formData);
  }

  // Agent Version
  getAgentVersion(): Observable<{ version: string; download_url?: string }> {
    return this.api.get('/system/agent-version');
  }
}
