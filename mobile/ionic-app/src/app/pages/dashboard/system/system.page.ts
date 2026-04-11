import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthService } from '../../../services/auth.service';
import { SystemService } from '../../../services/system.service';
import { SystemSettings, NotificationSettings } from '../../../models';

@Component({
  selector: 'app-system',
  templateUrl: './system.page.html',
  styleUrls: ['./system.page.scss'],
  standalone: false
})
export class SystemPage implements OnInit {
  systemInfo: { version: string; initialized: boolean } | null = null;
  settings: SystemSettings = {
    ssh_timeout: 30,
    idle_timeout: 300,
    max_connections_per_user: 10,
    login_rate_limit: 10,
    access_expiration: 15,
    refresh_expiration: 168,
    chart_color: 'smooth',
    timezone: 'UTC'
  };
  notificationSettings: NotificationSettings = {};
  loading = false;

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
  }

  async loadSystemInfo() {
    this.authService.getSystemInfo().subscribe({
      next: (info) => {
        this.systemInfo = info;
      },
      error: () => {}
    });
  }

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

  async performUpdate(downloadUrl: string) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('system.updating').toPromise()
    });
    await loading.present();

    this.authService.performUpdate(downloadUrl).subscribe({
      next: async () => {
        loading.dismiss();
        const toast = await this.toastController.create({
          message: await this.translate.get('system.updateSuccess').toPromise(),
          duration: 3000,
          color: 'success'
        });
        toast.present();
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

  async backupDatabase() {
    const loading = await this.loadingController.create({
      message: await this.translate.get('system.backupTitle').toPromise()
    });
    await loading.present();

    this.systemService.backupDatabase().subscribe({
      next: async (blob: Blob) => {
        loading.dismiss();
        // Create download link
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `termiscope_backup_${new Date().toISOString().split('T')[0]}.db`;
        a.click();
        window.URL.revokeObjectURL(url);
        
        const toast = await this.toastController.create({
          message: await this.translate.get('system.backupSuccess').toPromise(),
          duration: 2000,
          color: 'success'
        });
        toast.present();
      },
      error: async () => {
        loading.dismiss();
        const toast = await this.toastController.create({
          message: await this.translate.get('system.backupFailed').toPromise(),
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }
}
