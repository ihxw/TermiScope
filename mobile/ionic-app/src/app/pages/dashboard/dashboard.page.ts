import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { MenuController, AlertController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { AuthStore } from '../../stores/auth.store';
import { ThemeStore } from '../../stores/theme.store';
import { LocaleStore } from '../../stores/locale.store';
import { AuthService } from '../../services/auth.service';

@Component({
  selector: 'app-dashboard',
  templateUrl: './dashboard.page.html',
  styleUrls: ['./dashboard.page.scss'],
  standalone: false
})
export class DashboardPage implements OnInit {
  appPages = [
    { title: 'nav.terminal', url: '/dashboard/terminal', icon: 'terminal', requiresAdmin: false },
    { title: 'nav.monitor', url: '/dashboard/monitor', icon: 'pulse', requiresAdmin: false },
    { title: 'nav.fileTransfer', url: '/dashboard/transfer', icon: 'swap-horizontal', requiresAdmin: false },
    { title: 'nav.hosts', url: '/dashboard/hosts', icon: 'server', requiresAdmin: false },
    { title: 'nav.history', url: '/dashboard/history', icon: 'time', requiresAdmin: false },
    { title: 'nav.commands', url: '/dashboard/commands', icon: 'flash', requiresAdmin: false },
    { title: 'nav.recordings', url: '/dashboard/recordings', icon: 'videocam', requiresAdmin: false },
    { title: 'nav.users', url: '/dashboard/users', icon: 'people', requiresAdmin: true },
    { title: 'nav.system', url: '/dashboard/system', icon: 'settings', requiresAdmin: true },
  ];

  backendVersion = '...';
  frontendVersion = '1.4.8';

  constructor(
    private router: Router,
    private menuCtrl: MenuController,
    public authStore: AuthStore,
    public themeStore: ThemeStore,
    public localeStore: LocaleStore,
    private authService: AuthService,
    private alertController: AlertController,
    private translate: TranslateService
  ) {}

  async ngOnInit() {
    // Get backend version
    try {
      const info = await this.authService.getSystemInfo().toPromise();
      if (info) {
        this.backendVersion = info.version;
      }
    } catch (error) {
      console.error('Failed to get system info:', error);
    }
  }

  get filteredPages() {
    return this.appPages.filter(page => !page.requiresAdmin || this.authStore.isAdmin);
  }

  closeMenu() {
    this.menuCtrl.close();
  }

  async logout() {
    const alert = await this.alertController.create({
      header: await this.translate.get('auth.logout').toPromise(),
      message: await this.translate.get('auth.logoutConfirm').toPromise(),
      buttons: [
        {
          text: await this.translate.get('common.cancel').toPromise(),
          role: 'cancel'
        },
        {
          text: await this.translate.get('auth.logout').toPromise(),
          handler: () => {
            this.authStore.logout().subscribe(() => {
              this.router.navigate(['/login']);
            });
          }
        }
      ]
    });
    await alert.present();
  }

  goToProfile() {
    this.router.navigate(['/dashboard/profile']);
    this.closeMenu();
  }
}
