import { Component, OnInit, OnDestroy, AfterViewInit, ViewChild, ElementRef } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { ApiService } from '../services/api.service';
import { HostService, Host } from '../services/host.service';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { AlertController, ToastController } from '@ionic/angular';

@Component({
  selector: 'app-terminal',
  templateUrl: './terminal.page.html',
  styleUrls: ['./terminal.page.scss'],
  standalone: false
})
export class TerminalPage implements OnInit, OnDestroy, AfterViewInit {
  @ViewChild('terminalContainer', { static: false }) terminalContainer!: ElementRef;

  hosts: Host[] = [];
  selectedHostId: number | null = null;

  hostId: string | null = null; // Current active connection
  hostName: string | null = null;

  isConnected = false;

  private term: Terminal | null = null;
  private fitAddon: FitAddon | null = null;
  private ws: WebSocket | null = null;
  private resizeObserver: any;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private api: ApiService,
    private hostService: HostService,
    private toastCtrl: ToastController
  ) { }

  ngOnInit() {
    this.loadHosts();

    // Check if passed via params (auto connect)
    const id = this.route.snapshot.queryParamMap.get('id');
    const name = this.route.snapshot.queryParamMap.get('name');
    if (id) {
      this.selectedHostId = parseInt(id);
      this.hostName = name;
      this.connectToHost();
    }
  }

  async loadHosts() {
    this.hosts = await this.hostService.fetchHosts();
  }

  ngAfterViewInit() {
    // Terminal init is now triggered by user action or auto-connect
  }

  ngOnDestroy() {
    this.cleanup();
  }

  connectToHost() {
    if (!this.selectedHostId) {
      this.showToast('请选择主机');
      return;
    }

    const host = this.hosts.find(h => h.id === this.selectedHostId);
    if (host) {
      this.hostId = host.id.toString();
      this.hostName = host.name;
      this.cleanup(); // Close existing

      // Wait for view to update (ngIf hostId)
      setTimeout(() => {
        this.initTerminal();
      }, 100);
    }
  }

  disconnect() {
    this.cleanup();
    this.hostId = null;
    this.hostName = null;
    this.isConnected = false;
  }

  onHostChange(event: any) {
    this.selectedHostId = event.detail.value;
    if (this.selectedHostId) {
      this.connectToHost();
    }
  }

  private initTerminal() {
    if (!this.terminalContainer) return;

    this.term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: 'monospace',
      theme: {
        background: '#ffffff',
        foreground: '#333333',
        cursor: '#333333',
        selectionBackground: 'rgba(0,0,0,0.3)'
      }
    });

    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);

    this.term.open(this.terminalContainer.nativeElement);

    setTimeout(() => {
      this.handleResize();
    }, 300);

    this.resizeObserver = new ResizeObserver(() => {
      this.handleResize();
    });
    this.resizeObserver.observe(this.terminalContainer.nativeElement);

    this.term.onData(data => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ type: 'input', data }));
      }
    });

    this.connectSSH();
  }

  private async connectSSH() {
    try {
      const res: any = await this.api.post('/auth/ws-ticket');
      const ticket = res.ticket;

      const savedUrl = localStorage.getItem('server_url');
      let wsHost = '';
      let wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';

      if (savedUrl) {
        const url = new URL(savedUrl);
        wsHost = url.host;
        wsProtocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      } else {
        wsHost = window.location.host || 'localhost:8080';
      }

      const wsUrl = `${wsProtocol}//${wsHost}/api/ws/ssh/${this.hostId}?ticket=${ticket}`;
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        this.term?.writeln('\x1b[32mSSH Connection Established\x1b[0m\r\n');
        this.isConnected = true;
        this.sendResize();
        this.term?.focus();
      };

      this.ws.onmessage = (event) => {
        if (!this.term) return;
        try {
          const msg = JSON.parse(event.data);
          if (msg && msg.type === 'connected') {
            this.term.writeln(`\r\n\x1b[32m${msg.data}\x1b[0m\r\n`);
          } else if (msg && msg.type === 'error') {
            this.term.writeln(`\r\n\x1b[31mError: ${msg.data}\x1b[0m\r\n`);
          } else if (msg && msg.type === 'input') {
            this.term.write(msg.data);
          }
        } catch (e) {
          this.term.write(event.data);
        }
      };

      this.ws.onclose = () => {
        this.isConnected = false;
        // Don't clutter with msg if disconnected by user
      };

      this.ws.onerror = (err) => {
        this.term?.writeln('\r\n\x1b[31mWebSocket Error\x1b[0m\r\n');
        this.isConnected = false;
      };

    } catch (e) {
      this.term?.writeln('\r\n\x1b[31mFailed to authenticate SSH WebSocket\x1b[0m\r\n');
      this.isConnected = false;
    }
  }

  private handleResize() {
    if (this.fitAddon && this.term) {
      try {
        this.fitAddon.fit();
        this.sendResize();
      } catch (e) { }
    }
  }

  private sendResize() {
    if (this.ws && this.ws.readyState === WebSocket.OPEN && this.term) {
      this.ws.send(JSON.stringify({
        type: 'resize',
        data: {
          cols: this.term.cols,
          rows: this.term.rows
        }
      }));
    }
  }

  public sendKey(key: string) {
    if (this.term && this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type: 'input', data: key }));
      this.term.focus();
    }
  }

  openCommands() {
    this.router.navigate(['/commands']);
  }

  openRecordings() {
    this.router.navigate(['/recordings']);
  }

  private cleanup() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    if (this.term) {
      this.term.dispose();
      this.term = null;
    }
    this.isConnected = false;
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({ message: msg, duration: 2000 });
    toast.present();
  }
}
