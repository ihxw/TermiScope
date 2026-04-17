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
  selectedHosts: number[] = [];
  private ws: WebSocket | null = null;
  private reconnectTimer: any = null;
  connected = false;

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
    this.connectMonitorStream();
  }

  ngOnDestroy() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.disconnectMonitorStream();
  }

  private getWsServerUrl(): string {
    const serverUrl = this.apiService.getServerUrl();
    if (serverUrl) {
      return serverUrl.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:');
    }
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.host}`;
  }

  /**
   * 连接 Monitor WebSocket 流
   * 认证方式：获取一次性 ws-ticket，通过 URL query param 传递
   * 服务端 Stream handler 直接验证 ticket（与 SSH WebSocket 相同模式）
   */
  connectMonitorStream() {
    this.authService.getWSTicket().subscribe({
      next: (response: any) => {
        const ticket = response.ticket;
        const wsUrl = `${this.getWsServerUrl()}/api/monitor/stream?token=${ticket}`;

        try {
          this.ws = new WebSocket(wsUrl);
        } catch (e) {
          console.error('[Monitor] WebSocket creation failed:', e);
          this.scheduleReconnect();
          return;
        }

        this.ws.onopen = () => {
          console.log('[Monitor] WebSocket connected');
          this.connected = true;
        };

        this.ws.onmessage = (event) => {
          try {
            const msg = JSON.parse(event.data);
            if (msg.type === 'init' || msg.type === 'update') {
              this.updateMonitorStatuses(msg.data);
            } else if (msg.type === 'agent_event') {
              const agentEvent = msg.data;
              const status = this.monitorStatuses.get(agentEvent.host_id);
              if (status) {
                status.agent_update_status = agentEvent.message;
                this.monitorStatuses.set(agentEvent.host_id, status);
              }
            } else if (msg.type === 'remove') {
              this.monitorStatuses.delete(msg.data);
            }
          } catch (e) {
            console.error('[Monitor] Parse error:', e);
          }
        };

        this.ws.onclose = () => {
          console.log('[Monitor] WebSocket closed');
          this.connected = false;
          this.scheduleReconnect();
        };

        this.ws.onerror = () => {
          this.connected = false;
        };
      },
      error: (err) => {
        console.error('[Monitor] Failed to get ticket:', err);
        this.scheduleReconnect();
      }
    });
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connectMonitorStream();
    }, 5000);
  }

  disconnectMonitorStream() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private updateMonitorStatuses(updates: any[]) {
    if (!updates) return;
    const now = Date.now();
    for (const update of updates) {
      if (update.host_id) {
        update._clientLastUpdated = now;
        this.monitorStatuses.set(update.host_id, update as MonitorStatusExtended);
      }
    }
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
        next: (hosts) => { this.hosts = hosts; },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('host.failLoad').toPromise(),
            duration: 3000, color: 'danger'
          });
          toast.present();
        }
      });
  }

  getHostStatus(hostId: number): MonitorStatusExtended | undefined {
    return this.monitorStatuses.get(hostId);
  }

  isOnline(hostId: number): boolean {
    const status = this.getHostStatus(hostId);
    if (!status || !status._clientLastUpdated) return false;
    return (Date.now() - status._clientLastUpdated) < 15000;
  }

  getCpuPercent(status: MonitorStatusExtended): number {
    return status.cpu ?? 0;
  }

  getMemPercent(status: MonitorStatusExtended): number {
    if (!status.mem_total) return 0;
    return Math.round(((status.mem_used ?? 0) / status.mem_total) * 100);
  }

  getDiskPercent(status: MonitorStatusExtended): number {
    if (status.disks && status.disks.length > 0) {
      const totalUsed = status.disks.reduce((s, d) => s + (d.used || 0), 0);
      const totalSize = status.disks.reduce((s, d) => s + (d.total || 0), 0);
      return totalSize === 0 ? 0 : Math.round((totalUsed / totalSize) * 100);
    }
    if (!status.disk_total) return 0;
    return Math.round(((status.disk_used ?? 0) / status.disk_total) * 100);
  }

  getDiskUsedTotal(status: MonitorStatusExtended): { used: number, total: number } {
    if (status.disks && status.disks.length > 0) {
      return {
        used: status.disks.reduce((s, d) => s + (d.used || 0), 0),
        total: status.disks.reduce((s, d) => s + (d.total || 0), 0)
      };
    }
    return { used: status.disk_used ?? 0, total: status.disk_total ?? 0 };
  }

  formatUptime(seconds: number): string {
    if (!seconds) return '-';
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (d > 0) return `${d}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  formatBytes(bytes: number): string {
    if (!bytes) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++; }
    return `${bytes.toFixed(1)} ${units[i]}`;
  }

  formatSpeed(bps: number): string {
    return bps ? this.formatBytes(bps) + '/s' : '0 B/s';
  }

  formatCpu(val: number): string {
    return (val || 0).toFixed(1);
  }

  get onlineHosts(): number {
    return this.hosts.filter(h => this.isOnline(h.id)).length;
  }

  get totalHosts(): number {
    return this.hosts.length;
  }

  // --- Host actions ---

  async deployMonitor(host: SSHHostExtended) {
    const alert = await this.alertController.create({
      header: await this.translate.get('monitor.deployAgent').toPromise(),
      message: await this.translate.get('monitor.deployConfirm', { name: host.name }).toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        { text: await this.translate.get('common.confirm').toPromise(), handler: () => this.doDeployMonitor(host) }
      ]
    });
    await alert.present();
  }

  private async doDeployMonitor(host: SSHHostExtended) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('monitor.deploying').toPromise()
    });
    await loading.present();
    this.sshService.deployMonitor(host.id)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          (await this.toastController.create({
            message: await this.translate.get('monitor.deploySuccess').toPromise(),
            duration: 2000, color: 'success'
          })).present();
        },
        error: async () => {
          (await this.toastController.create({
            message: await this.translate.get('monitor.deployFailed').toPromise(),
            duration: 3000, color: 'danger'
          })).present();
        }
      });
  }

  async stopMonitor(host: SSHHostExtended) {
    const alert = await this.alertController.create({
      header: await this.translate.get('monitor.stopMonitor').toPromise(),
      message: await this.translate.get('monitor.disableConfirm').toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        { text: await this.translate.get('common.confirm').toPromise(), handler: () => this.doStopMonitor(host) }
      ]
    });
    await alert.present();
  }

  private async doStopMonitor(host: SSHHostExtended) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('monitor.stopping').toPromise()
    });
    await loading.present();
    this.sshService.stopMonitor(host.id)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          (await this.toastController.create({
            message: await this.translate.get('monitor.stopSuccess').toPromise(),
            duration: 2000, color: 'success'
          })).present();
        },
        error: async () => {
          (await this.toastController.create({
            message: await this.translate.get('monitor.stopFailed').toPromise(),
            duration: 3000, color: 'danger'
          })).present();
        }
      });
  }

  // --- Selection ---

  toggleHostSelection(hostId: number) {
    const i = this.selectedHosts.indexOf(hostId);
    i > -1 ? this.selectedHosts.splice(i, 1) : this.selectedHosts.push(hostId);
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
    if (!this.selectedHosts.length) return;
    const alert = await this.alertController.create({
      header: await this.translate.get('monitor.batchDeploy').toPromise(),
      message: await this.translate.get('monitor.batchDeployConfirm', { count: this.selectedHosts.length }).toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        { text: await this.translate.get('common.confirm').toPromise(), handler: () => this.doBatchDeploy() }
      ]
    });
    await alert.present();
  }

  private async doBatchDeploy() {
    const loading = await this.loadingController.create({
      message: await this.translate.get('monitor.deploying').toPromise()
    });
    await loading.present();
    this.sshService.batchDeployMonitor(this.selectedHosts)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          (await this.toastController.create({
            message: await this.translate.get('monitor.batchDeploySuccess', { count: this.selectedHosts.length }).toPromise(),
            duration: 2000, color: 'success'
          })).present();
          this.selectedHosts = [];
        },
        error: async () => {
          (await this.toastController.create({
            message: await this.translate.get('monitor.batchDeployFailed').toPromise(),
            duration: 3000, color: 'danger'
          })).present();
        }
      });
  }
}
