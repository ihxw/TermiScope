import { Component, OnInit } from '@angular/core';
import { ApiService } from '../services/api.service';
import { Router } from '@angular/router';
import { ToastController } from '@ionic/angular';

@Component({
  selector: 'app-login',
  templateUrl: './login.page.html',
  styleUrls: ['./login.page.scss'],
  standalone: false
})
export class LoginPage implements OnInit {
  serverUrl = '';
  username = '';
  password = '';

  constructor(
    private api: ApiService,
    private router: Router,
    private toastController: ToastController
  ) { }

  ngOnInit() {
    this.serverUrl = localStorage.getItem('server_url') || '';
  }

  async onSubmit() {
    if (!this.username || !this.password || !this.serverUrl) {
      return;
    }

    try {
      // Update ApiService baseURL before login
      this.api.updateBaseUrl(this.serverUrl);
      const response: any = await this.api.post('/auth/login', {
        username: this.username,
        password: this.password,
        remember: true
      });

      // API service already unwraps response.data.data if success is true
      // Web logic: this.token = response.token
      if (response && response.token) {
        localStorage.setItem('token', response.token);
        if (response.refresh_token) {
          localStorage.setItem('refresh_token', response.refresh_token);
        }

        const toast = await this.toastController.create({
          message: '登录成功',
          duration: 2000,
          color: 'success'
        });
        toast.present();

        this.router.navigate(['/dashboard'], { replaceUrl: true });
      } else if (response && response.requires_2fa) {
        // TODO: Implement 2FA
        const toast = await this.toastController.create({
          message: '需要 2FA 验证，移动端暂未实现',
          duration: 3000,
          color: 'warning'
        });
        toast.present();
      }

    } catch (error: any) {
      console.error(error);
      // Error handling is partly done in interceptor, but we might want custom handling here if needed
    }
  }
}
