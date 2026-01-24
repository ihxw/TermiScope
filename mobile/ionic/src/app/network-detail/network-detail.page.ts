import { Component, OnInit, OnDestroy } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { HostService, Host } from '../services/host.service';
import { ApiService } from '../services/api.service';
import { AlertController, ToastController } from '@ionic/angular';

@Component({
  selector: 'app-network-detail',
  templateUrl: './network-detail.page.html',
  styleUrls: ['./network-detail.page.scss'],
  standalone: false
})
export class NetworkDetailPage implements OnInit, OnDestroy {
  hostId: number | null = null;
  host: Host | undefined;
  loading = false;

  // Real-time data
  private socket: WebSocket | null = null;
  connected = false;

  // Stats
  monthlyRx = 0;
  monthlyTx = 0;
  currentRxRate = 0;
  currentTxRate = 0;
  interfaces: any[] = [];

  // Config
  segment = 'overview'; // overview | config
  config = {
    net_interface_list: [] as string[],
    net_reset_day: 1,
    limit_gb: 0,
    adjustment_gb: 0,
    net_traffic_counter_mode: 'total'
  };
  saving = false;

  constructor(
    private route: ActivatedRoute,
    private hostService: HostService,
    private api: ApiService,
    private toastCtrl: ToastController
  ) { }

  ngOnInit() {
    const id = this.route.snapshot.queryParamMap.get('id');
    if (id) {
      this.hostId = parseInt(id);
      this.loadData();
      this.connectWS();
    }
  }

  ngOnDestroy() {
    if (this.socket) {
      this.socket.close();
    }
  }

  async loadData() {
    this.loading = true;
    try {
      const hosts = await this.hostService.fetchHosts();
      this.host = hosts.find(h => h.id === this.hostId);
      if (this.host) {
        this.initConfig();
      }
    } finally {
      this.loading = false;
    }
  }

  initConfig() {
    if (!this.host) return;

    const h = this.host as any; // Cast to access dynamic props if interface incomplete
    let list: string[] = [];
    const netInterface = h['net_interface'] || 'auto';
    if (netInterface && netInterface !== '') {
      list = netInterface.split(',');
    } else {
      list = ['auto'];
    }

    this.config = {
      net_interface_list: list,
      net_reset_day: h['net_reset_day'] || 1,
      limit_gb: parseFloat(((h['net_traffic_limit'] || 0) / (1024 * 1024 * 1024)).toFixed(2)),
      adjustment_gb: parseFloat(((h['net_traffic_used_adjustment'] || 0) / (1024 * 1024 * 1024)).toFixed(2)),
      net_traffic_counter_mode: h['net_traffic_counter_mode'] || 'total'
    };

    // Init stats (static until WS updates)
    this.monthlyRx = h['net_rx'] || 0;
    this.monthlyTx = h['net_tx'] || 0;
  }

  async connectWS() {
    try {
      const res: any = await this.api.post('/auth/ws-ticket');
      const ticket = res.ticket;
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';

      const savedUrl = localStorage.getItem('server_url');
      let wsHost = '';
      let wsProtocol = protocol;

      if (savedUrl) {
        const url = new URL(savedUrl);
        wsHost = url.host;
        wsProtocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      } else {
        wsHost = window.location.host || 'localhost:8080';
      }

      const wsUrl = `${wsProtocol}//${wsHost}/api/monitor/stream?token=${ticket}`;

      this.socket = new WebSocket(wsUrl);

      this.socket.onopen = () => { this.connected = true; };

      this.socket.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          if (msg.type === 'init' || msg.type === 'update') {
            const dataList = msg.data;
            if (Array.isArray(dataList)) {
              const myData = dataList.find((h: any) => h.host_id === this.hostId);
              if (myData) {
                // Update dynamic stats
                this.currentRxRate = myData.net_rx_rate || 0;
                this.currentTxRate = myData.net_tx_rate || 0;
                this.monthlyRx = myData.net_monthly_rx || 0;
                this.monthlyTx = myData.net_monthly_tx || 0;
                if (myData.interfaces) {
                  this.interfaces = myData.interfaces;
                }
              }
            }
          }
        } catch (e) { }
      };

      this.socket.onclose = () => { this.connected = false; };

    } catch (e) {
      console.error('WS Connect failed', e);
    }
  }

  async saveConfig() {
    if (!this.hostId) return;
    this.saving = true;
    try {
      const trafficLimit = Math.floor(this.config.limit_gb * 1024 * 1024 * 1024);
      const trafficAdj = Math.floor(this.config.adjustment_gb * 1024 * 1024 * 1024);

      // Handle string or array input for interface list
      let interfaceStr = '';
      if (Array.isArray(this.config.net_interface_list)) {
        interfaceStr = this.config.net_interface_list.join(',');
      } else {
        interfaceStr = this.config.net_interface_list; // User might type a string in ion-input
      }

      await this.hostService.updateHost(this.hostId, {
        net_interface: interfaceStr,
        net_reset_day: this.config.net_reset_day,
        net_traffic_limit: trafficLimit,
        net_traffic_used_adjustment: trafficAdj,
        net_traffic_counter_mode: this.config.net_traffic_counter_mode
      });

      this.showToast('配置已保存');
    } catch (e) {
      this.showToast('保存失败');
    } finally {
      this.saving = false;
    }
  }

  doRefresh(event: any) {
    this.loadData().then(() => event.target.complete());
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({ message: msg, duration: 2000 });
    toast.present();
  }
}
