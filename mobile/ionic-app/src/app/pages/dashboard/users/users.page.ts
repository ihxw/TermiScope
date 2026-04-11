import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { UserService } from '../../../services/user.service';
import { User } from '../../../models';

@Component({
  selector: 'app-users',
  templateUrl: './users.page.html',
  styleUrls: ['./users.page.scss'],
  standalone: false
})
export class UsersPage implements OnInit {
  users: User[] = [];
  loading = false;
  page = 1;
  pageSize = 20;

  constructor(
    private userService: UserService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadUsers();
  }

  async loadUsers() {
    this.loading = true;
    this.userService.getUsers(this.page, this.pageSize)
      .subscribe({
        next: (result: any) => {
          this.users = result.items || [];
          this.loading = false;
        },
        error: async () => {
          this.loading = false;
          const toast = await this.toastController.create({
            message: await this.translate.get('user.loadFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async addUser() {
    const alert = await this.alertController.create({
      header: await this.translate.get('user.addUser').toPromise(),
      inputs: [
        { name: 'username', type: 'text', placeholder: await this.translate.get('user.enterUsername').toPromise() },
        { name: 'email', type: 'email', placeholder: await this.translate.get('user.enterValidEmail').toPromise() },
        { name: 'password', type: 'password', placeholder: await this.translate.get('user.enterPassword').toPromise() },
        { name: 'role', type: 'radio', label: 'Admin', value: 'admin' },
        { name: 'role', type: 'radio', label: 'User', value: 'user' }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.save').toPromise(),
          handler: (data) => {
            if (data.username && data.password) {
              this.createUser(data);
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async createUser(data: any) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.userService.createUser(data)
      .subscribe({
        next: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('user.createdSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.loadUsers();
        },
        error: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('user.saveFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async toggleUserStatus(user: User) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.userService.toggleUserStatus(user.id, !user.is_active)
      .subscribe({
        next: async () => {
          loading.dismiss();
          user.is_active = !user.is_active;
          const toast = await this.toastController.create({
            message: await this.translate.get('user.updatedSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('user.saveFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async deleteUser(user: User) {
    const alert = await this.alertController.create({
      header: await this.translate.get('user.deleteUser').toPromise(),
      message: user.username,
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.delete').toPromise(),
          role: 'destructive',
          handler: () => {
            this.userService.deleteUser(user.id).subscribe({
              next: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('user.userDeleted').toPromise(),
                  duration: 2000,
                  color: 'success'
                });
                toast.present();
                this.loadUsers();
              },
              error: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('user.deleteFailed').toPromise(),
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
}
