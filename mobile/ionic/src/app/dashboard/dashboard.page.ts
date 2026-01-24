import { Component, OnInit, OnDestroy } from '@angular/core';
import { HostService, Host } from '../services/host.service';
import { Observable } from 'rxjs';
import { Router } from '@angular/router';
import { AlertController, ToastController } from '@ionic/angular';

@Component({
  selector: 'app-dashboard',
  templateUrl: './dashboard.page.html',
  styleUrls: ['./dashboard.page.scss'],
  standalone: false
})
export class DashboardPage implements OnInit, OnDestroy {
  hosts$: Observable<Host[]>;
  loading = false;

  constructor(
    private hostService: HostService,
    private router: Router,
    private alertCtrl: AlertController,
    private toastCtrl: ToastController
  ) {
    this.hosts$ = this.hostService.hosts$;
  }

  ngOnInit() {
    this.loadData();
    this.hostService.connectToMonitor();
  }

  ngOnDestroy() {
    this.hostService.disconnect();
  }

  async loadData() {
    this.loading = true;
    try {
      await this.hostService.fetchHosts();
    } finally {
      this.loading = false;
    }
  }

  refresh() {
    this.loadData();
  }

  doRefresh(event: any) {
    this.loadData().then(() => {
      event.target.complete();
    });
  }

  getOsIcon(os: string | undefined): string {
    const lower = (os || '').toLowerCase();
    if (lower.includes('win')) return 'logo-windows';
    if (lower.includes('mac') || lower.includes('darwin')) return 'logo-apple';
    if (lower.includes('linux') || lower.includes('ubuntu') || lower.includes('debian')) return 'logo-tux';
    return 'desktop-outline';
  }

  isOffline(host: Host): boolean {
    if (!host.last_updated) return true;
    const now = Date.now() / 1000;
    return (now - host.last_updated) > 15;
  }

  getStatusColor(percent: number | undefined): string {
    const p = percent || 0;
    if (p >= 90) return 'danger';
    if (p >= 80) return 'warning';
    return 'success';
  }

  calcPct(used: number | undefined, total: number | undefined): number {
    if (!total || !used) return 0;
    return Math.round((used / total) * 100);
  }

  formatBytes(bytes: number | undefined): string {
    if (!bytes) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  }

  formatSpeed(bytesPerSec: number | undefined): string {
    return this.formatBytes(bytesPerSec) + '/s';
  }

  formatUptime(seconds: number | undefined): string {
    if (!seconds) return '-';
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);

    const parts = [];
    if (days > 0) parts.push(`${days}d`);
    if (hours > 0) parts.push(`${hours}h`);
    if (minutes > 0) parts.push(`${minutes}m`);
    if (parts.length === 0) return '0m';
    return parts.join(' ');
  }

  connect(host: Host) {
    this.router.navigate(['/terminal'], { queryParams: { id: host.id, name: host.name } });
  }

  viewHistory(host: Host) {
    this.router.navigate(['/history'], { queryParams: { hostId: host.id } });
  }

  async viewSettings(host: Host) {
    const alert = await this.alertCtrl.create({
      header: 'Edit Host',
      inputs: [
        { name: 'name', type: 'text', value: host.name, placeholder: 'Name' },
        { name: 'host', type: 'text', value: host.host, placeholder: 'Host/IP' },
      ],
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Update',
          handler: (data) => {
            this.hostService.updateHost(host.id, { ...host, ...data });
            this.showToast('Updated successfully');
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  viewNetwork(host: Host) {
    this.router.navigate(['/network-detail'], { queryParams: { id: host.id } });
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({ message: msg, duration: 2000 });
    toast.present();
  }
}
