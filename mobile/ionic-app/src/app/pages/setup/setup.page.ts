import { Component } from '@angular/core';
import { FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { AlertController, LoadingController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthService } from '../../services/auth.service';
import { AuthStore } from '../../stores/auth.store';

@Component({
  selector: 'app-setup',
  templateUrl: './setup.page.html',
  styleUrls: ['./setup.page.scss'],
  standalone: false
})
export class SetupPage {
  setupForm: FormGroup;

  constructor(
    private fb: FormBuilder,
    private router: Router,
    private authService: AuthService,
    private authStore: AuthStore,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private translate: TranslateService
  ) {
    this.setupForm = this.fb.group({
      username: ['', [Validators.required, Validators.minLength(3)]],
      password: ['', [Validators.required, Validators.minLength(6)]],
      confirmPassword: ['', [Validators.required]]
    }, { validators: this.passwordMatchValidator });
  }

  passwordMatchValidator(form: FormGroup) {
    const password = form.get('password')?.value;
    const confirmPassword = form.get('confirmPassword')?.value;
    return password === confirmPassword ? null : { passwordMismatch: true };
  }

  async onSubmit() {
    if (this.setupForm.invalid) {
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('setup.submit').toPromise(),
      spinner: 'crescent'
    });
    await loading.present();

    const { username, password } = this.setupForm.value;

    this.authService.initialize(username, password).subscribe({
      next: (response) => {
        loading.dismiss();
        this.authStore.setAuth(response);
        this.router.navigate(['/dashboard/terminal']);
      },
      error: async (error) => {
        loading.dismiss();
        const message = error.error?.error || 'Setup failed';
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
}
