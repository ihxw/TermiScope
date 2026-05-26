import { Component } from '@angular/core';
import { FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { AlertController, LoadingController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthService } from '../../services/auth.service';

@Component({
  selector: 'app-forgot-password',
  templateUrl: './forgot-password.page.html',
  styleUrls: ['./forgot-password.page.scss'],
  standalone: false
})
export class ForgotPasswordPage {
  forgotForm: FormGroup;
  emailSent = false;

  constructor(
    private fb: FormBuilder,
    private router: Router,
    private authService: AuthService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private translate: TranslateService
  ) {
    this.forgotForm = this.fb.group({
      email: ['', [Validators.required, Validators.email]]
    });
  }

  async onSubmit() {
    if (this.forgotForm.invalid) {
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise(),
      spinner: 'crescent'
    });
    await loading.present();

    const { email } = this.forgotForm.value;

    this.authService.forgotPassword(email).subscribe({
      next: async () => {
        loading.dismiss();
        this.emailSent = true;
      },
      error: async (error) => {
        loading.dismiss();
        const message = error.error?.error || await this.translate.get('common.error').toPromise();
        this.showAlert(message);
      }
    });
  }

  async showAlert(message: string) {
    const alert = await this.alertController.create({
      header: await this.translate.get('common.error').toPromise(),
      message,
      buttons: ['OK']
    });
    await alert.present();
  }

  backToLogin() {
    this.router.navigate(['/login']);
  }
}
