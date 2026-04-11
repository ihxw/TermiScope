import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthService } from '../../../services/auth.service';
import { TwoFAService } from '../../../services/twofa.service';
import { AuthStore } from '../../../stores/auth.store';
import { User } from '../../../models';
import { finalize } from 'rxjs/operators';

@Component({
  selector: 'app-profile',
  templateUrl: './profile.page.html',
  styleUrls: ['./profile.page.scss'],
  standalone: false
})
export class ProfilePage implements OnInit {
  user: User | null = null;
  loading = false;
  
  // 2FA
  twoFAEnabled = false;
  twoFASetupData: { secret: string; qr_code: string; backup_codes: string[] } | null = null;
  showQRCode = false;
  verificationCode = '';

  // Password change
  passwordData = {
    current: '',
    new: '',
    confirm: ''
  };

  constructor(
    private authService: AuthService,
    private twoFAService: TwoFAService,
    private authStore: AuthStore,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadUser();
  }

  loadUser() {
    this.user = this.authStore.user;
    this.twoFAEnabled = false; // TODO: Get from user profile
  }

  async changePassword() {
    if (!this.passwordData.current || !this.passwordData.new || !this.passwordData.confirm) {
      const toast = await this.toastController.create({
        message: await this.translate.get('auth.passwordRequired').toPromise(),
        duration: 3000,
        color: 'warning'
      });
      toast.present();
      return;
    }

    if (this.passwordData.new !== this.passwordData.confirm) {
      const toast = await this.toastController.create({
        message: await this.translate.get('auth.passwordMismatch').toPromise(),
        duration: 3000,
        color: 'warning'
      });
      toast.present();
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.authService.changePassword(this.passwordData.current, this.passwordData.new)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('auth.passwordChanged').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.passwordData = { current: '', new: '', confirm: '' };
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('common.saveFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async setup2FA() {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.twoFAService.setup2FA()
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async (data: any) => {
          this.twoFASetupData = data;
          this.showQRCode = true;
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.setupFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async verify2FASetup() {
    if (!this.verificationCode || this.verificationCode.length !== 6) {
      const toast = await this.toastController.create({
        message: await this.translate.get('twofa.verificationCodeRequired').toPromise(),
        duration: 3000,
        color: 'warning'
      });
      toast.present();
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.twoFAService.verify2FASetup(this.verificationCode)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async (data: any) => {
          this.twoFAEnabled = true;
          this.showQRCode = false;
          this.twoFASetupData = { ...this.twoFASetupData!, backup_codes: data.backup_codes };
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.setupSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.verifyFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async disable2FA() {
    const alert = await this.alertController.create({
      header: await this.translate.get('twofa.disable').toPromise(),
      message: await this.translate.get('twofa.disableWarning').toPromise(),
      inputs: [
        { name: 'code', type: 'text', placeholder: await this.translate.get('twofa.verificationCodePlaceholder').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: (data) => {
            if (data.code) {
              this.doDisable2FA(data.code);
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async doDisable2FA(code: string) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.twoFAService.disable2FA(code)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          this.twoFAEnabled = false;
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.disableSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('twofa.verifyFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  cancel2FASetup() {
    this.showQRCode = false;
    this.twoFASetupData = null;
    this.verificationCode = '';
  }
}
