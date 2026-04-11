import { Injectable } from '@angular/core';
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

  verify2FASetup(code: string): Observable<{ backup_codes: string[] }> {
    return this.api.post<{ backup_codes: string[] }>('/auth/2fa/verify-setup', { code });
  }

  verify2FA(code: string): Observable<{ valid: boolean }> {
    return this.api.post<{ valid: boolean }>('/auth/2fa/verify', { code });
  }

  disable2FA(code: string): Observable<any> {
    return this.api.post('/auth/2fa/disable', { code });
  }

  regenerateBackupCodes(code: string): Observable<{ backup_codes: string[] }> {
    return this.api.post<{ backup_codes: string[] }>('/auth/2fa/backup-codes', { code });
  }
}
