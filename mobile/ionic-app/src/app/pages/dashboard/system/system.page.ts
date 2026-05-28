import { Component, OnInit, OnDestroy } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthService } from '../../../services/auth.service';
import { SystemService } from '../../../services/system.service';
import { finalize } from 'rxjs/operators';

@Component({
  selector: 'app-system',
  templateUrl: './system.page.html',
  styleUrls: ['./system.page.scss'],
  standalone: false
})
export class SystemPage implements OnInit, OnDestroy {
  systemInfo: { version: string; initialized: boolean } | null = null;
  loading = false;
  activeTab: 'settings' | 'backup' = 'settings';

  // Settings form - 与 Web 端一致，包含所有字段
  settings: any = {
    timezone: 'Local',
    ssh_timeout: '30s',
    idle_timeout: '30m',
    max_connections_per_user: 10,
    login_rate_limit: 20,
    access_expiration: '60m',
    refresh_expiration: '168h',
    smtp_server: '',
    smtp_port: '',
    smtp_user: '',
    smtp_password: '',
    smtp_from: '',
    smtp_to: '',
    smtp_tls_skip_verify: false,
    telegram_bot_token: '',
    telegram_chat_id: '',
    notification_template: ''
  };

  settingsLoading = false;
  sendingTestEmail = false;
  sendingTestTelegram = false;

  // Update status
  private updateStatusTimer: any = null;

  constructor(
    private authService: AuthService,
    private systemService: SystemService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadSystemInfo();
    this.loadSettings();
  }

  ngOnDestroy() {
    if (this.updateStatusTimer) {
      clearInterval(this.updateStatusTimer);
    }
  }

  async loadSystemInfo() {
    this.authService.getSystemInfo().subscribe({
      next: (info) => {
        this.systemInfo = info;
      },
      error: () => {}
    });
  }

  // Web 端: GET /system/settings 获取所有设置（含通知）
  async loadSettings() {
    this.systemService.getSettings().subscribe({
      next: (data: any) => {
        Object.assign(this.settings, data);
        // Auto-fill default template if empty
        if (!this.settings.notification_template) {
          this.settings.notification_template = this.defaultNotificationTemplate;
        }
      },
      error: async () => {
        const toast = await this.toastController.create({
          message: await this.translate.get('system.fetchSettingsFailed').toPromise(),
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }

  get defaultNotificationTemplate(): string {
    return `{{emoji}}{{emoji}}{{emoji}}
Event: {{event}}
Clients: {{client}}
Message: {{message}}
Time: {{time}}`;
  }

  resetNotificationTemplate() {
    this.settings.notification_template = this.defaultNotificationTemplate;
  }

  // Web 端: PUT /system/settings 保存所有设置
  async saveSettings() {
    this.settingsLoading = true;
    this.systemService.saveSettings(this.settings)
      .pipe(finalize(() => this.settingsLoading = false))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('system.saveSettingsSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async (err: any) => {
          const msg = err?.error?.error || await this.translate.get('system.saveSettingsFailed').toPromise();
          const toast = await this.toastController.create({
            message: msg,
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  // Test Email
  async testEmail() {
    this.sendingTestEmail = true;
    const payload = {
      smtp_server: this.settings.smtp_server,
      smtp_port: this.settings.smtp_port,
      smtp_user: this.settings.smtp_user,
      smtp_password: this.settings.smtp_password,
      smtp_from: this.settings.smtp_from,
      smtp_to: this.settings.smtp_to,
      smtp_tls_skip_verify: this.settings.smtp_tls_skip_verify
    };
    this.systemService.testEmail(payload)
      .pipe(finalize(() => this.sendingTestEmail = false))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('system.testEmailSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async (err: any) => {
          const msg = err?.error?.error || await this.translate.get('system.testEmailFailed').toPromise();
          const toast = await this.toastController.create({
            message: msg,
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  // Test Telegram
  async testTelegram() {
    this.sendingTestTelegram = true;
    this.systemService.testTelegram({
      telegram_bot_token: this.settings.telegram_bot_token,
      telegram_chat_id: this.settings.telegram_chat_id
    })
      .pipe(finalize(() => this.sendingTestTelegram = false))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('system.testTelegramSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async (err: any) => {
          const msg = err?.error?.error || await this.translate.get('system.testTelegramFailed').toPromise();
          const toast = await this.toastController.create({
            message: msg,
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  // Web 端: POST /system/check-update
  async checkUpdate() {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.authService.checkUpdate().subscribe({
      next: async (result: any) => {
        loading.dismiss();
        if (result.update_available) {
          const alert = await this.alertController.create({
            header: await this.translate.get('system.updateAvailable', { version: result.version }).toPromise(),
            message: result.body || '',
            buttons: [
              { text: await this.translate.get('common.cancel').toPromise() },
              {
                text: await this.translate.get('system.updateNow').toPromise(),
                handler: () => {
                  this.performUpdate(result.download_url);
                }
              }
            ]
          });
          await alert.present();
        } else {
          const toast = await this.toastController.create({
            message: 'No updates available',
            duration: 2000,
            color: 'success'
          });
          toast.present();
        }
      },
      error: async () => {
        loading.dismiss();
        const toast = await this.toastController.create({
          message: 'Failed to check for updates',
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }

  // Web 端: POST /system/upgrade + 轮询 GET /system/update-status
  async performUpdate(downloadUrl: string) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('system.updating').toPromise()
    });
    await loading.present();

    this.authService.performUpdate(downloadUrl).subscribe({
      next: async () => {
        // Start polling for update status
        this.updateStatusTimer = setInterval(() => {
          this.authService.getUpdateStatus().subscribe({
            next: (status: any) => {
              if (status.status === 'finished' || status.status === 'error') {
                clearInterval(this.updateStatusTimer);
                loading.dismiss();
                if (status.status === 'finished') {
                  this.showToast('system.updateSuccess', 'success');
                } else {
                  this.showToast('system.updateFailed', 'danger');
                }
              }
            },
            error: () => {
              clearInterval(this.updateStatusTimer);
              loading.dismiss();
            }
          });
        }, 2000);
      },
      error: async () => {
        loading.dismiss();
        const toast = await this.toastController.create({
          message: await this.translate.get('system.updateFailed').toPromise(),
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }

  // Web 端: POST /system/backup 返回 { filename, ticket }，然后构造下载 URL
  async backupDatabase() {
    const alert = await this.alertController.create({
      header: await this.translate.get('system.backupPasswordTitle').toPromise(),
      message: await this.translate.get('system.backupPasswordDesc').toPromise(),
      inputs: [
        { name: 'password', type: 'password', placeholder: await this.translate.get('system.passwordPlaceholder').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: (data) => {
            this.doBackup(data.password || '');
          }
        }
      ]
    });
    await alert.present();
  }

  async doBackup(password: string) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('system.backupTitle').toPromise()
    });
    await loading.present();

    this.systemService.backupDatabase(password)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async (response: any) => {
          if (response && response.filename && response.ticket) {
            // Construct download URL with one-time ticket
            const downloadUrl = this.systemService.getBackupDownloadUrl(response.filename, response.ticket);
            window.open(downloadUrl, '_blank');
            const toast = await this.toastController.create({
              message: await this.translate.get('system.backupSuccess').toPromise(),
              duration: 2000,
              color: 'success'
            });
            toast.present();
          }
        },
        error: async (err: any) => {
          const msg = err?.error?.error || await this.translate.get('system.backupFailed').toPromise();
          const toast = await this.toastController.create({
            message: msg,
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  // Restore - Web 端: 先选文件，输入密码，然后 POST /system/restore (multipart)
  async restoreDatabase() {
    // Use file input to select backup file
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.db';
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) return;

      // Ask for password
      const alert = await this.alertController.create({
        header: await this.translate.get('system.restorePasswordTitle').toPromise(),
        message: await this.translate.get('system.restorePasswordDesc').toPromise(),
        inputs: [
          { name: 'password', type: 'password', placeholder: await this.translate.get('system.passwordPlaceholder').toPromise() }
        ],
        buttons: [
          { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
          {
            text: await this.translate.get('common.confirm').toPromise(),
            handler: (data) => {
              this.doRestore(file, data.password || '');
            }
          }
        ]
      });
      await alert.present();
    };
    input.click();
  }

  async doRestore(file: File, password: string) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('system.restoreTitle').toPromise()
    });
    await loading.present();

    this.systemService.restoreDatabase(file, password)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('system.restoreSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          // Reload after restore
          setTimeout(() => window.location.reload(), 2000);
        },
        error: async (err: any) => {
          if (err?.status === 403) {
            const toast = await this.toastController.create({
              message: await this.translate.get('system.incorrectPassword').toPromise(),
              duration: 3000,
              color: 'danger'
            });
            toast.present();
          } else {
            const msg = err?.error?.error || await this.translate.get('system.restoreFailed').toPromise();
            const toast = await this.toastController.create({
              message: msg,
              duration: 3000,
              color: 'danger'
            });
            toast.present();
          }
        }
      });
  }

  private async showToast(key: string, color: string) {
    const toast = await this.toastController.create({
      message: await this.translate.get(key).toPromise(),
      duration: 2000,
      color
    });
    toast.present();
  }
}
