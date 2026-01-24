import { Component } from '@angular/core';
import { Router } from '@angular/router';

@Component({
  selector: 'app-root',
  templateUrl: 'app.component.html',
  styleUrls: ['app.component.scss'],
  standalone: false,
})
export class AppComponent {
  public appPages = [
    { title: '监控', url: '/dashboard', icon: 'speedometer' },
    { title: '终端', url: '/terminal', icon: 'terminal' },
    { title: '主机', url: '/hosts', icon: 'server' },
    { title: '状态历史', url: '/history', icon: 'time' },
    { title: '命令', url: '/commands', icon: 'flash' },
    { title: '录制', url: '/recordings', icon: 'videocam' },
    { title: '用户', url: '/user-management', icon: 'people' },
    { title: '系统设置', url: '/system-settings', icon: 'settings' },
  ];

  constructor(private router: Router) { }

  logout() {
    localStorage.removeItem('token');
    localStorage.removeItem('refresh_token');
    this.router.navigate(['/login']);
  }

  closeMenu() {
    const menu = document.querySelector('ion-menu');
    if (menu) menu.close();
  }
}
