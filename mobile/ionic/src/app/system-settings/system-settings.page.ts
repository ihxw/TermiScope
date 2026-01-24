import { Component, OnInit } from '@angular/core';
import { UserService } from '../services/user.service';
import { ToastController, LoadingController, AlertController } from '@ionic/angular';

@Component({
  selector: 'app-system-settings',
  templateUrl: './system-settings.page.html',
  styleUrls: ['./system-settings.page.scss'],
  standalone: false
})
export class SystemSettingsPage implements OnInit {
  settings: any = {};
  agentVersion: any = {};

  constructor(
    private userService: UserService,
    private toastCtrl: ToastController,
    private loadingCtrl: LoadingController,
    private alertCtrl: AlertController
  ) { }

  ngOnInit() {
    this.loadData();
  }

  async loadData() {
    try {
      this.settings = await this.userService.getSystemSettings();
      this.agentVersion = await this.userService.getAgentVersion();
    } catch (e) {
      // this.showToast('无法获取系统设置 (需要管理员权限)');
    }
  }

  async saveSettings() {
    try {
      await this.userService.updateSystemSettings(this.settings);
      this.showToast('设置已保存');
    } catch (e) {
      this.showToast('保存失败');
    }
  }

  async backup() {
    const loading = await this.loadingCtrl.create({ message: '备份中...' });
    await loading.present();
    try {
      const blob: any = await this.userService.backupSystem();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `termiscope-backup-${new Date().toISOString()}.db`;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
      this.showToast('备份下载已开始');
    } catch (e) {
      this.showToast('备份失败');
    } finally {
      loading.dismiss();
    }
  }

  async restore(event: any) {
    const file = event.target.files[0];
    if (!file) return;

    const alert = await this.alertCtrl.create({
      header: '确认恢复',
      message: '恢复操作将覆盖当前数据库，系统将重启。确定继续吗？',
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '确定',
          handler: async () => {
            const loading = await this.loadingCtrl.create({ message: '恢复中...' });
            await loading.present();
            try {
              await this.userService.restoreSystem(file);
              this.showToast('恢复成功，请重启服务');
            } catch (e) {
              this.showToast('恢复失败');
            } finally {
              loading.dismiss();
              event.target.value = '';
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({ message: msg, duration: 2000 });
    toast.present();
  }
}
