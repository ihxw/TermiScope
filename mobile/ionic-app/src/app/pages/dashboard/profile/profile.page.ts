import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthService } from '../../../services/auth.service';
import { TwoFAService } from '../../../services/twofa.service';
import { AuthStore } from '../../../stores/auth.store';
import { User, LoginHistory } from '../../../models';
import { finalize } from 'rxjs/operators';

@Component({
  selector: 'app-profile',
  templateUrl: './profile.page.html',
  styleUrls: ['./profile.page.scss'],
  standalone: false
})
export class ProfilePage implements OnInit {
  user: User | null = null;
  loading = false;
  
  // 2FA
  twoFAEnabled = false;
  twoFASetupData: { secret: string; qr_code: string; backup_codes: string[] } | null = null;
  showQRCode = false;
  verificationCode = '';
  backupCodes: string[] = [];
  showBackupCodes = false;

  // Password change
  passwordData = {
    current: '',
    new: '',
    confirm: ''
  };

  // Login History - Web 端有完整的分页登录历史和会话管理
  loginHistory: LoginHistory[] = [];
  historyLoading = false;
  historyPage = 1;
  historyPageSize = 10;
  historyTotal = 0;

  // Active Tab
  activeTab: 'basic' | 'history' | 'sessions' = 'basic';

  constructor(
    private authService: AuthService,
    private twoFAService: TwoFAService,
    private authStore: AuthStore,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadUser();
  }

  loadUser() {
    this.user = this.authStore.user;
    this.twoFAEnabled = (this.user as any)?.two_factor_enabled || false;
  }

  onTabChange(event: any) {
    this.activeTab = event.detail.value;
    if (this.activeTab === 'history' || this.activeTab === 'sessions') {
      this.loadLoginHistory();
    }
  }

  // Login History - 与 Web 端一致
  async loadLoginHistory() {
    this.historyLoading = true;
    this.authService.getLoginHistory(this.historyPage, this.historyPageSize)
      .pipe(finalize(() => this.historyLoading = false))
      .subscribe({
        next: (result: any) => {
          this.loginHistory = result.data || [];
          this.historyTotal = result.pagination?.total || 0;
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: 'Failed to load login history',
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  get activeSessions(): LoginHistory[] {
    return this.loginHistory.filter(h => (h.status as string)?.toLowerCase() === 'active');
  }

  async revokeSession(jti: string) {
    const alert = await this.alertController.create({
      header: await this.translate.get('history.revokeConfirm').toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: () => {
            this.authService.revokeSession(jti).subscribe({
              next: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('history.revokeSuccess').toPromise(),
                  duration: 2000,
                  color: 'success'
                });
                toast.present();
                this.loadLoginHistory();
              },
              error: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('history.revokeFailed').toPromise(),
                  duration: 3000,
                  color: 'danger'
                });
                toast.present();
              }
            });
          }
        }
      ]
    });
    await alert.present();
  }

  formatDate(dateStr: string): string {
    if (!dateStr) return '-';
    return new Date(dateStr).toLocaleString();
  }

  getStatusColor(status: string): string {
    switch (status?.toLowerCase()) {
      case 'active': return 'success';
      case 'revoked': return 'danger';
      default: return 'medium';
    }
  }

  async changePassword() {
    if (!this.passwordData.current || !this.passwordData.new || !this.passwordData.confirm) {
      const toast = await this.toastController.create({
        message: await this.translate.get('auth.passwordRequired').toPromise(),
        duration: 3000,
        color: 'warning'
      });
      toast.present();
      return;
    }

    if (this.passwordData.new !== this.passwordData.confirm) {
      const toast = await this.toastController.create({
        message: await this.translate.get('auth.passwordMismatch').toPromise(),
        duration: 3000,
        color: 'warning'
      });
      toast.present();
      return;
    }

    if (this.passwordData.new.length < 6) {
      const toast = await this.toastController.create({
        message: await this.translate.get('auth.passwordMinLength').toPromise(),
        duration: 3000,
        color: 'warning'
      });
      toast.present();
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.authService.changePassword(this.passwordData.current, this.passwordData.new)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('auth.passwordChanged').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.passwordData = { current: '', new: '', confirm: '' };
        },
        error: async (err: any) => {
          const msg = err?.error?.error || await this.translate.get('common.saveFailed').toPromise();
          const toast = await this.toastController.create({
            message: msg,
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async setup2FA() {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.twoFAService.setup2FA()
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async (data: any) => {
          this.twoFASetupData = data;
          this.showQRCode = true;
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.setupFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  // Web 端: verify2FASetup 需要传 secret (通过 X-2FA-Secret header)
  async verify2FASetup() {
    if (!this.verificationCode || this.verificationCode.length !== 6) {
      const toast = await this.toastController.create({
        message: await this.translate.get('twofa.verificationCodeRequired').toPromise(),
        duration: 3000,
        color: 'warning'
      });
      toast.present();
      return;
    }

    if (!this.twoFASetupData?.secret) {
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    // Web 端传 code + secret（通过 header 传递 secret）
    this.twoFAService.verify2FASetup(this.verificationCode, this.twoFASetupData.secret)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async (data: any) => {
          this.twoFAEnabled = true;
          this.showQRCode = false;
          // Web 端返回 { codes: [...] }
          this.backupCodes = data.codes || [];
          this.showBackupCodes = true;
          // Refresh user info
          this.authService.getCurrentUser().subscribe(user => {
            this.authStore.setUser(user);
            this.user = user;
          });
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.setupSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.verifyFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async disable2FA() {
    const alert = await this.alertController.create({
      header: await this.translate.get('twofa.disable').toPromise(),
      message: await this.translate.get('twofa.disableWarning').toPromise(),
      inputs: [
        { name: 'code', type: 'text', placeholder: await this.translate.get('twofa.verificationCodePlaceholder').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: (data) => {
            if (data.code) {
              this.doDisable2FA(data.code);
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async doDisable2FA(code: string) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.twoFAService.disable2FA(code)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          this.twoFAEnabled = false;
          // Refresh user info
          this.authService.getCurrentUser().subscribe(user => {
            this.authStore.setUser(user);
            this.user = user;
          });
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.disableSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.verifyFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  // Web 端: regenerateBackupCodes 不需要 code 参数
  async regenerateBackupCodes() {
    const alert = await this.alertController.create({
      header: await this.translate.get('twofa.regenerateBackupCodes').toPromise(),
      message: await this.translate.get('twofa.regenerateConfirm').toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: () => {
            this.doRegenerateBackupCodes();
          }
        }
      ]
    });
    await alert.present();
  }

  async doRegenerateBackupCodes() {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.twoFAService.regenerateBackupCodes()
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async (data: any) => {
          this.backupCodes = data.codes || [];
          this.showBackupCodes = true;
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.backupCodesRegenerated').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.regenerateFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  cancel2FASetup() {
    this.showQRCode = false;
    this.twoFASetupData = null;
    this.verificationCode = '';
  }

  dismissBackupCodes() {
    this.showBackupCodes = false;
    this.backupCodes = [];
  }
}
