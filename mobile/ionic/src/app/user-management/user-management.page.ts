import { Component, OnInit } from '@angular/core';
import { UserService } from '../services/user.service';
import { AlertController, ToastController, LoadingController } from '@ionic/angular';

@Component({
  selector: 'app-user-management',
  templateUrl: './user-management.page.html',
  styleUrls: ['./user-management.page.scss'],
  standalone: false
})
export class UserManagementPage implements OnInit {
  users: any[] = [];
  loading = false;

  constructor(
    private userService: UserService,
    private alertCtrl: AlertController,
    private toastCtrl: ToastController,
    private loadingCtrl: LoadingController
  ) { }

  ngOnInit() {
    this.loadUsers();
  }

  async loadUsers() {
    this.loading = true;
    try {
      this.users = await this.userService.getUsers();
    } catch (e) {
      this.showToast('无法获取用户列表 (需要管理员权限)');
    } finally {
      this.loading = false;
    }
  }

  async doRefresh(event: any) {
    await this.loadUsers();
    event.target.complete();
  }

  async addUser() {
    const alert = await this.alertCtrl.create({
      header: '新增用户',
      inputs: [
        { name: 'username', type: 'text', placeholder: '用户名' },
        { name: 'password', type: 'password', placeholder: '密码' },
        { name: 'role', type: 'text', placeholder: '角色 (admin/user)', value: 'user' }
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '创建',
          handler: async (data) => {
            if (!data.username || !data.password) return false;
            try {
              await this.userService.createUser(data);
              this.showToast('用户已创建');
              this.loadUsers();
              return true;
            } catch (e) {
              this.showToast('创建失败');
              return false;
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async editUser(user: any) {
    const alert = await this.alertCtrl.create({
      header: '编辑用户',
      inputs: [
        { name: 'password', type: 'password', placeholder: '重置密码 (留空不修改)' },
        { name: 'role', type: 'text', value: user.role, placeholder: '角色' }
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '保存',
          handler: async (data) => {
            const payload: any = { role: data.role };
            if (data.password) payload.password = data.password;

            try {
              await this.userService.updateUser(user.id, payload);
              this.showToast('更新成功');
              this.loadUsers();
              return true;
            } catch (e) {
              this.showToast('更新失败');
              return false;
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async deleteUser(user: any) {
    const alert = await this.alertCtrl.create({
      header: '确认删除',
      message: `删除用户 ${user.username}?`,
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '删除',
          role: 'destructive',
          handler: async () => {
            try {
              await this.userService.deleteUser(user.id);
              this.showToast('已删除');
              this.loadUsers();
            } catch (e) {
              this.showToast('删除失败');
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
