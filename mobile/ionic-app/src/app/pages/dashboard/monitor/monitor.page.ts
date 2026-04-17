import { Component, OnInit, OnDestroy } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { SSHService } from '../../../services/ssh.service';
import { AuthService } from '../../../services/auth.service';
import { ApiService } from '../../../services/api.service';
import { MonitorStatusExtended, SSHHostExtended } from '../../../models';
import { finalize } from 'rxjs/operators';

@Component({
  selector: 'app-monitor',
  templateUrl: './monitor.page.html',
  styleUrls: ['./monitor.page.scss'],
  standalone: false
})
export class MonitorPage implements OnInit, OnDestroy {
  hosts: SSHHostExtended[] = [];
  monitorStatuses: Map<number, MonitorStatusExtended> = new Map();
  loading = false;
  viewMode: 'card' | 'list' = 'card';
  refreshInterval: any;
  selectedHosts: number[] = [];
  private ws: WebSocket | null = null;
  private reconnectTimer: any = null;

  constructor(
    private sshService: SSHService,
    private authService: AuthService,
    private apiService: ApiService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadHosts();
    // Connect to monitor stream WebSocket
    this.connectMonitorStream();
  }

  ngOnDestroy() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
    }
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    this.disconnectMonitorStream();
  }

  getWsServerUrl(): string {
    // Get WebSocket URL from configured API server
    const serverUrl = this.apiService.getServerUrl();
    if (serverUrl) {
      // Convert http/https to ws/wss
      return serverUrl.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:');
    }
    // Fallback to current location
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host;
    return `${protocol}//${host}`;
  }

  connectMonitorStream() {
    // Get WebSocket ticket first
    this.authService.getWSTicket().subscribe({
      next: (response: any) => {
        const ticket = response.ticket;
        const serverUrl = this.getWsServerUrl();
        const wsUrl = `${serverUrl}/api/monitor/stream?token=${ticket}`;
        
        this.ws = new WebSocket(wsUrl);
        
        this.ws.onopen = () => {
          console.log('[Monitor] WebSocket connected');
        };
        
        this.ws.onmessage = (event) => {
          try {
            const msg = JSON.parse(event.data);
            if (msg.type === 'init' || msg.type === 'update') {
              this.updateMonitorStatuses(msg.data);
            }
          } catch (e) {
            console.error('[Monitor] Failed to parse message:', e);
          }
        };
        
        this.ws.onclose = () => {
          console.log('[Monitor] WebSocket closed, reconnecting...');
          this.reconnectTimer = setTimeout(() => this.connectMonitorStream(), 3000);
        };
        
        this.ws.onerror = (error) => {
          console.error('[Monitor] WebSocket error:', error);
        };
      },
      error: () => {
        console.error('[Monitor] Failed to get WebSocket ticket');
        this.reconnectTimer = setTimeout(() => this.connectMonitorStream(), 5000);
      }
    });
  }

  disconnectMonitorStream() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  updateMonitorStatuses(updates: any[]) {
    if (!updates) return;
    updates.forEach((update: any) => {
      if (update.host_id) {
        this.monitorStatuses.set(update.host_id, update as MonitorStatusExtended);
      }
    });
  }

  async loadHosts() {
    this.loading = true;
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.sshService.getHosts()
      .pipe(finalize(() => {
        this.loading = false;
        loading.dismiss();
      }))
      .subscribe({
        next: (hosts) => {
          this.hosts = hosts;
          this.refreshStatuses();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('host.failLoad').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  refreshStatuses() {
    // 监控状态完全通过 WebSocket /monitor/stream 获取
    // 不再调用错误的 testConnection API
    // 如果 WebSocket 未连接，尝试重新连接
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      this.connectMonitorStream();
    }
  }

  getHostStatus(hostId: number): MonitorStatusExtended | undefined {
    return this.monitorStatuses.get(hostId);
  }

  isOnline(hostId: number): boolean {
    const status = this.getHostStatus(hostId);
    return status ? status.status === 'running' : false;
  }

  formatUptime(seconds: number): string {
    if (!seconds) return '-';
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  formatBytes(bytes: number): string {
    if (!bytes) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (bytes >= 1024 && i < units.length - 1) {
      bytes /= 1024;
      i++;
    }
    return `${bytes.toFixed(1)} ${units[i]}`;
  }

  formatSpeed(bytesPerSec: number): string {
    if (!bytesPerSec) return '0 B/s';
    return this.formatBytes(bytesPerSec) + '/s';
  }

  get onlineHosts(): number {
    return this.hosts.filter(h => this.isOnline(h.id)).length;
  }

  get totalHosts(): number {
    return this.hosts.length;
  }

  async deployMonitor(host: SSHHostExtended) {
    const alert = await this.alertController.create({
      header: await this.translate.get('monitor.deployAgent').toPromise(),
      message: await this.translate.get('monitor.deployConfirm', { name: host.name }).toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: () => {
            this.doDeployMonitor(host);
          }
        }
      ]
    });
    await alert.present();
  }

  async doDeployMonitor(host: SSHHostExtended) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('monitor.deploying').toPromise()
    });
    await loading.present();

    this.sshService.deployMonitor(host.id)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.deploySuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.refreshStatuses();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.deployFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async stopMonitor(host: SSHHostExtended) {
    const alert = await this.alertController.create({
      header: await this.translate.get('monitor.stopMonitor').toPromise(),
      message: await this.translate.get('monitor.disableConfirm').toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: () => {
            this.doStopMonitor(host);
          }
        }
      ]
    });
    await alert.present();
  }

  async doStopMonitor(host: SSHHostExtended) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('monitor.stopping').toPromise()
    });
    await loading.present();

    this.sshService.stopMonitor(host.id)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.stopSuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.refreshStatuses();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.stopFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  toggleHostSelection(hostId: number) {
    const index = this.selectedHosts.indexOf(hostId);
    if (index > -1) {
      this.selectedHosts.splice(index, 1);
    } else {
      this.selectedHosts.push(hostId);
    }
  }

  isSelected(hostId: number): boolean {
    return this.selectedHosts.includes(hostId);
  }

  get hasSelection(): boolean {
    return this.selectedHosts.length > 0;
  }

  selectAllHosts() {
    this.selectedHosts = this.hosts.map(h => h.id);
  }

  async batchDeploy() {
    if (this.selectedHosts.length === 0) return;
    
    const alert = await this.alertController.create({
      header: await this.translate.get('monitor.batchDeploy').toPromise(),
      message: await this.translate.get('monitor.batchDeployConfirm', { count: this.selectedHosts.length }).toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: () => {
            this.doBatchDeploy();
          }
        }
      ]
    });
    await alert.present();
  }

  async doBatchDeploy() {
    const loading = await this.loadingController.create({
      message: await this.translate.get('monitor.deploying').toPromise()
    });
    await loading.present();

    this.sshService.batchDeployMonitor(this.selectedHosts)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.batchDeploySuccess', { count: this.selectedHosts.length }).toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.selectedHosts = [];
          this.refreshStatuses();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.batchDeployFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }
}
