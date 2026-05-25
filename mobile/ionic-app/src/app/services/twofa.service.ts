import { Injectable } from '@angular/core';
import { HttpHeaders } from '@angular/common/http';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import { TwoFASetup } from '../models';

@Injectable({
  providedIn: 'root'
})
export class TwoFAService {
  constructor(private api: ApiService) {}

  setup2FA(): Observable<TwoFASetup> {
    return this.api.post<TwoFASetup>('/auth/2fa/setup', {});
  }

  // Web 端: POST /auth/2fa/verify-setup + X-2FA-Secret header
  verify2FASetup(code: string, secret: string): Observable<{ codes: string[] }> {
    return this.api.post<{ codes: string[] }>('/auth/2fa/verify-setup', { code }, {
      headers: { 'X-2FA-Secret': secret }
    });
  }

  verify2FA(code: string): Observable<{ valid: boolean }> {
    return this.api.post<{ valid: boolean }>('/auth/2fa/verify', { code });
  }

  disable2FA(code: string): Observable<any> {
    return this.api.post('/auth/2fa/disable', { code });
  }

  // Web 端: POST /auth/2fa/backup-codes 无需 code 参数
  regenerateBackupCodes(): Observable<{ codes: string[] }> {
    return this.api.post<{ codes: string[] }>('/auth/2fa/backup-codes', {});
  }
}
