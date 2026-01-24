import { Component, OnInit } from '@angular/core';
import { UserService } from '../services/user.service';
import { AlertController, ToastController, LoadingController } from '@ionic/angular';

@Component({
  selector: 'app-profile',
  templateUrl: './profile.page.html',
  styleUrls: ['./profile.page.scss'],
  standalone: false
})
export class ProfilePage implements OnInit {
  user: any = {};
  qrcode: string | null = null;
  secret: string | null = null;
  setupMode = false;
  verifyToken = '';

  constructor(
    private userService: UserService,
    private alertCtrl: AlertController,
    private toastCtrl: ToastController,
    private loadingCtrl: LoadingController
  ) { }

  ngOnInit() {
    this.loadUser();
  }

  async loadUser() {
    try {
      this.user = await this.userService.getCurrentUser();
    } catch (e) {
      this.showToast('无法获取用户信息');
    }
  }

  async changePassword() {
    const alert = await this.alertCtrl.create({
      header: '修改密码',
      inputs: [
        { name: 'currentPassword', type: 'password', placeholder: '当前密码' },
        { name: 'newPassword', type: 'password', placeholder: '新密码' },
        { name: 'confirmPassword', type: 'password', placeholder: '确认新密码' }
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '确定',
          handler: async (data) => {
            if (data.newPassword !== data.confirmPassword) {
              this.showToast('两次密码不一致');
              return false;
            }
            if (!data.currentPassword || !data.newPassword) {
              this.showToast('请输入密码');
              return false;
            }
            try {
              await this.userService.changePassword({
                old_password: data.currentPassword,
                new_password: data.newPassword
              });
              this.showToast('密码修改成功');
              return true;
            } catch (e: any) {
              this.showToast('修改失败: ' + (e.error || e.message));
              return false;
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async setup2FA() {
    const loading = await this.loadingCtrl.create();
    await loading.present();
    try {
      const res = await this.userService.setup2FA();
      if (res.qr_code && !res.qr_code.startsWith('data:')) {
        this.qrcode = `data:image/png;base64,${res.qr_code}`;
      } else {
        this.qrcode = res.qr_code;
      }
      this.secret = res.secret;
      this.setupMode = true;
    } catch (e) {
      this.showToast('无法开启 2FA Setup');
    } finally {
      loading.dismiss();
    }
  }

  async verifySetup() {
    if (!this.verifyToken) {
      this.showToast('请输入验证码');
      return;
    }
    try {
      await this.userService.verifySetup2FA(this.verifyToken, this.secret!);
      this.showToast('2FA 设置成功');
      this.setupMode = false;
      this.qrcode = null;
      this.loadUser();
    } catch (e) {
      this.showToast('验证失败');
    }
  }

  cancelSetup() {
    this.setupMode = false;
    this.qrcode = null;
    this.secret = null;
  }

  async disable2FA() {
    const alert = await this.alertCtrl.create({
      header: '关闭 2FA',
      inputs: [
        { name: 'password', type: 'password', placeholder: '当前密码' }
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '确定',
          handler: async (data) => {
            if (!data.password) return false;
            try {
              await this.userService.disable2FA(data.password);
              this.showToast('2FA 已关闭');
              this.loadUser();
              return true;
            } catch (e) {
              this.showToast('关闭失败');
              return false;
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
