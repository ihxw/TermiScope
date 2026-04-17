import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { ToastController, LoadingController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthService } from '../../services/auth.service';
import { finalize } from 'rxjs/operators';

@Component({
  selector: 'app-reset-password',
  templateUrl: './reset-password.page.html',
  styleUrls: ['./reset-password.page.scss'],
  standalone: false
})
export class ResetPasswordPage implements OnInit {
  token: string = '';
  password: string = '';
  confirmPassword: string = '';
  loading = false;
  error: string = '';

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private authService: AuthService,
    private toastController: ToastController,
    private loadingController: LoadingController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    // Get token from URL query params
    this.route.queryParams.subscribe(params => {
      this.token = params['token'] || '';
    });
  }

  async resetPassword() {
    if (!this.token) {
      this.error = await this.translate.get('auth.invalidToken').toPromise() || 'Invalid token';
      return;
    }

    if (!this.password || !this.confirmPassword) {
      this.error = await this.translate.get('auth.passwordRequired').toPromise();
      return;
    }

    if (this.password !== this.confirmPassword) {
      this.error = await this.translate.get('auth.passwordMismatch').toPromise();
      return;
    }

    if (this.password.length < 6) {
      this.error = await this.translate.get('auth.passwordMinLength').toPromise();
      return;
    }

    this.error = '';
    this.loading = true;

    const loadingEl = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loadingEl.present();

    // Web 端: POST /auth/reset-password { token, password }
    this.authService.resetPassword(this.token, this.password)
      .pipe(finalize(() => {
        this.loading = false;
        loadingEl.dismiss();
      }))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('auth.passwordResetSuccess').toPromise() || 'Password reset successfully',
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.router.navigate(['/login']);
        },
        error: async (err: any) => {
          this.error = err?.error?.error || await this.translate.get('common.error').toPromise();
        }
      });
  }

  goToLogin() {
    this.router.navigate(['/login']);
  }
}
