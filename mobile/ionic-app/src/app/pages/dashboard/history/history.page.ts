import { Component, OnInit } from '@angular/core';
import { LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { ConnectionLogService } from '../../../services/data.service';
import { AuthService } from '../../../services/auth.service';
import { ConnectionLog, LoginHistory } from '../../../models';

@Component({
  selector: 'app-history',
  templateUrl: './history.page.html',
  styleUrls: ['./history.page.scss'],
  standalone: false
})
export class HistoryPage implements OnInit {
  activeTab: 'ssh' | 'web' = 'ssh';
  sshLogs: ConnectionLog[] = [];
  webLogs: LoginHistory[] = [];
  loading = false;
  page = 1;
  pageSize = 20;

  constructor(
    private connectionLogService: ConnectionLogService,
    private authService: AuthService,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadSSHLogs();
    this.loadWebLogs();
  }

  async loadSSHLogs() {
    this.loading = true;
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.connectionLogService.getLogs(this.page, this.pageSize)
      .subscribe({
        next: (result: any) => {
          this.sshLogs = result.items || [];
          this.loading = false;
          loading.dismiss();
        },
        error: async () => {
          this.loading = false;
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('history.loadSshFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async loadWebLogs() {
    this.loading = true;
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.authService.getLoginHistory(this.page, this.pageSize)
      .subscribe({
        next: (result: any) => {
          this.webLogs = result.items || [];
          this.loading = false;
          loading.dismiss();
        },
        error: async () => {
          this.loading = false;
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('history.loadWebFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  setTab(tab: any) {
    this.activeTab = tab as 'ssh' | 'web';
  }

  formatDuration(seconds: number): string {
    if (!seconds) return '-';
    const hours = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  formatDate(dateStr: string): string {
    if (!dateStr) return '-';
    return new Date(dateStr).toLocaleString();
  }
}
