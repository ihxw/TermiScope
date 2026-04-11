import { Component, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router, ActivatedRoute } from '@angular/router';
import { AlertController, LoadingController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthStore } from '../../stores/auth.store';
import { ApiService } from '../../services/api.service';
import { AuthService } from '../../services/auth.service';

@Component({
  selector: 'app-login',
  templateUrl: './login.page.html',
  styleUrls: ['./login.page.scss'],
  standalone: false
})
export class LoginPage implements OnInit {
  loginForm: FormGroup;
  twoFAForm: FormGroup;
  
  requires2FA = false;
  tempUserId: number | null = null;
  tempToken: string | null = null;
  
  showServerConfig = false;
  serverUrl = '';
  
  backendVersion = '...';
  frontendVersion = '1.4.8';

  constructor(
    private fb: FormBuilder,
    private router: Router,
    private route: ActivatedRoute,
    private authStore: AuthStore,
    private apiService: ApiService,
    private authService: AuthService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private translate: TranslateService
  ) {
    this.loginForm = this.fb.group({
      username: ['', [Validators.required]],
      password: ['', [Validators.required]],
      remember: [false]
    });

    this.twoFAForm = this.fb.group({
      code: ['', [Validators.required, Validators.minLength(6), Validators.maxLength(39)]]
    });
  }

  async ngOnInit() {
    this.serverUrl = this.apiService.getServerUrl();
    
    // Check if system needs initialization
    try {
      const initStatus = await this.authService.checkInit().toPromise();
      if (!initStatus?.initialized) {
        this.router.navigate(['/setup']);
        return;
      }
    } catch (error) {
      console.error('Failed to check init status:', error);
    }

    // Get backend version
    try {
      const info = await this.authService.getSystemInfo().toPromise();
      if (info) {
        this.backendVersion = info.version;
      }
    } catch (error) {
      console.error('Failed to get system info:', error);
      this.backendVersion = 'unknown';
    }
  }

  async onLogin() {
    if (this.loginForm.invalid) {
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('auth.login').toPromise(),
      spinner: 'crescent'
    });
    await loading.present();

    const { username, password, remember } = this.loginForm.value;

    this.authStore.login(username, password, remember).subscribe({
      next: (response) => {
        loading.dismiss();
        
        if (response.requires_2fa) {
          this.requires2FA = true;
          this.tempUserId = response.user_id || null;
          this.tempToken = response.temp_token || null;
        } else {
          this.onLoginSuccess();
        }
      },
      error: async (error) => {
        loading.dismiss();
        const message = error.error?.error || await this.translate.get('auth.loginFailed').toPromise();
        this.showAlert(message);
      }
    });
  }

  async onVerify2FA() {
    if (this.twoFAForm.invalid || !this.tempUserId || !this.tempToken) {
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('twofa.verify').toPromise(),
      spinner: 'crescent'
    });
    await loading.present();

    const { code } = this.twoFAForm.value;

    this.authStore.verify2FA(this.tempUserId, code, this.tempToken).subscribe({
      next: () => {
        loading.dismiss();
        this.onLoginSuccess();
      },
      error: async (error) => {
        loading.dismiss();
        const message = error.error?.error || await this.translate.get('twofa.verifyFailed').toPromise();
        this.showAlert(message);
      }
    });
  }

  private onLoginSuccess() {
    const redirect = this.route.snapshot.queryParams['redirect'] || '/dashboard/terminal';
    this.router.navigateByUrl(redirect);
  }

  async showAlert(message: string) {
    const alert = await this.alertController.create({
      header: await this.translate.get('common.error').toPromise(),
      message,
      buttons: ['OK']
    });
    await alert.present();
  }

  toggleServerConfig() {
    this.showServerConfig = !this.showServerConfig;
  }

  saveServerUrl() {
    if (this.serverUrl) {
      this.apiService.setServerUrl(this.serverUrl);
      this.showServerConfig = false;
    }
  }

  backToLogin() {
    this.requires2FA = false;
    this.tempUserId = null;
    this.tempToken = null;
    this.twoFAForm.reset();
  }

  goToForgotPassword() {
    this.router.navigate(['/forgot-password']);
  }
}
