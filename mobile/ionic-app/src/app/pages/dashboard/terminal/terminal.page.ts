import { Component, OnInit, ViewChild, ElementRef, OnDestroy } from '@angular/core';
import { AlertController, LoadingController, ModalController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { SSHService } from '../../../services/ssh.service';
import { AuthService } from '../../../services/auth.service';
import { ApiService } from '../../../services/api.service';
import { SSHHostExtended } from '../../../models';
import { finalize } from 'rxjs/operators';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';

interface TerminalSession {
  id: string;
  hostId: number;
  hostName: string;
  ws?: WebSocket;
  connected: boolean;
  terminal?: Terminal;
  fitAddon?: FitAddon;
  container?: HTMLElement;
}

@Component({
  selector: 'app-terminal',
  templateUrl: './terminal.page.html',
  styleUrls: ['./terminal.page.scss'],
  standalone: false
})
export class TerminalPage implements OnInit, OnDestroy {
  hosts: SSHHostExtended[] = [];
  sessions: TerminalSession[] = [];
  activeSessionId: string | null = null;
  loading = false;
  showKeyboardToolbar = true;
  showSftp = false;
  terminalSize = '';
  modifiers = {
    ctrl: false,
    alt: false,
    shift: false
  };
  quickConnectData = {
    host: '',
    port: 22,
    username: '',
    password: '',
    authType: 'password' as 'password' | 'key'
  };

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
  }

  getOsIcon(os?: string): string {
    if (!os) return 'server-outline';
    const osLower = os.toLowerCase();
    if (osLower.includes('windows')) return 'logo-windows';
    if (osLower.includes('mac') || osLower.includes('darwin') || osLower.includes('apple')) return 'logo-apple';
    if (osLower.includes('linux') || osLower.includes('ubuntu') || osLower.includes('centos') || osLower.includes('debian')) return 'logo-tux';
    return 'server-outline';
  }

  ngOnDestroy() {
    // Clean up all terminals
    this.sessions.forEach(session => {
      if (session.terminal) {
        session.terminal.dispose();
      }
      if (session.ws) {
        session.ws.close();
      }
    });
  }

  ionViewDidEnter() {
    // Fit terminal when view becomes active
    this.fitActiveTerminal();
  }

  fitActiveTerminal() {
    const session = this.activeSession;
    if (session?.fitAddon) {
      setTimeout(() => session.fitAddon!.fit(), 100);
    }
  }

  async loadHosts() {
    this.loading = true;
    this.sshService.getHosts().subscribe({
      next: (hosts) => {
        this.hosts = hosts.filter((h: SSHHostExtended) => h.host_type !== 'monitor');
        this.loading = false;
      },
      error: async () => {
        this.loading = false;
        const toast = await this.toastController.create({
          message: await this.translate.get('host.failLoad').toPromise(),
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }

  async connectToHost(host: SSHHostExtended) {
    // Optional: focus already connected session instead of duplicating (mimics part of Web logic)
    const existingSession = this.sessions.find(s => s.hostId === host.id);
    if (existingSession) {
      this.activeSessionId = existingSession.id;
      this.fitActiveTerminal();
      return;
    }

    const loading = await this.loadingController.create({
      message: await this.translate.get('terminal.connecting').toPromise()
    });
    await loading.present();

    // Get WebSocket ticket
    this.authService.getWSTicket().subscribe({
      next: async (response: any) => {
        const ticket = response.ticket;
        const sessionId = `session_${Date.now()}_${host.id}`;
        
        // Create WebSocket connection
        const serverUrl = this.getWsServerUrl();
        const wsUrl = `${serverUrl}/api/ws/ssh/${host.id}?ticket=${ticket}`;
        
        const ws = new WebSocket(wsUrl);
        ws.binaryType = 'arraybuffer';
        
        // Create terminal
        const terminal = new Terminal({
          cursorBlink: true,
          fontSize: 14,
          fontFamily: 'monospace',
          theme: {
            background: '#1e1e1e',
            foreground: '#d4d4d4'
          }
        });
        
        const fitAddon = new FitAddon();
        terminal.loadAddon(fitAddon);
        
        ws.onopen = () => {
          loading.dismiss();
          const session: TerminalSession = {
            id: sessionId,
            hostId: host.id,
            hostName: host.name,
            ws: ws,
            connected: true,
            terminal: terminal,
            fitAddon: fitAddon
          };
          this.sessions.push(session);
          this.activeSessionId = sessionId;
          
          // Terminal will be attached in the view after render
          setTimeout(() => this.attachTerminal(session), 200);
        };

        ws.onmessage = (event) => {
          if (event.data instanceof ArrayBuffer) {
            const data = new Uint8Array(event.data);
            terminal.write(data);
          }
        };

        ws.onclose = () => {
          const session = this.sessions.find(s => s.id === sessionId);
          if (session) {
            session.connected = false;
          }
          terminal.writeln('\r\n\x1b[31mConnection closed.\x1b[0m');
        };

        ws.onerror = async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('terminal.connectionFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        };
        
        // Handle terminal input
        terminal.onData((data) => {
          if (ws.readyState === WebSocket.OPEN) {
            // Send as JSON message like Web端
            ws.send(JSON.stringify({ type: 'input', data: data }));
          }
        });
        
        // Handle terminal resize
        terminal.onResize(({ cols, rows }) => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'resize', data: { cols, rows } }));
          }
        });
      },
      error: async () => {
        loading.dismiss();
        const toast = await this.toastController.create({
          message: await this.translate.get('terminal.connectionFailed').toPromise(),
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }
  
  attachTerminal(session: TerminalSession) {
    if (!session.terminal) return;
    
    const container = document.getElementById('term-wrap-' + session.id);
    if (!container) return;
    container.innerHTML = '';
    session.terminal.open(container);
    session.container = container;
    
    setTimeout(() => {
      if (session.fitAddon) {
        session.fitAddon.fit();
      }
    }, 100);
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

  closeSession(sessionId: string) {
    const index = this.sessions.findIndex(s => s.id === sessionId);
    if (index > -1) {
      const session = this.sessions[index];
      if (session.ws) {
        session.ws.close();
      }
      this.sessions.splice(index, 1);
      
      if (this.activeSessionId === sessionId) {
        this.activeSessionId = this.sessions.length > 0 ? this.sessions[0].id : null;
      }
    }
  }

  setActiveSession(event: any) {
    const sessionId = event.detail ? event.detail.value : event;
    this.activeSessionId = sessionId;
    setTimeout(() => {
      this.fitActiveTerminal();
    }, 100);
  }

  handleHostSelect(event: any) {
    const host = event.detail.value;
    if (host && host.id) {
      this.connectToHost(host);
      // Reset the select so user can re-trigger
      event.target.value = null;
    }
  }

  get activeSession(): TerminalSession | undefined {
    return this.sessions.find(s => s.id === this.activeSessionId);
  }

  async quickConnect() {
    const alert = await this.alertController.create({
      header: await this.translate.get('terminal.quickConnect').toPromise(),
      inputs: [
        { name: 'host', type: 'text', placeholder: '192.168.1.100' },
        { name: 'port', type: 'number', value: '22', placeholder: '22' },
        { name: 'username', type: 'text', placeholder: 'root' },
        { name: 'password', type: 'password', placeholder: 'Password' }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('terminal.connect').toPromise(),
          handler: (data) => {
            if (data.host && data.username) {
              this.performQuickConnect(data);
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async performQuickConnect(data: any) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('terminal.connecting').toPromise()
    });
    await loading.present();

    // Get WebSocket ticket
    this.authService.getWSTicket().subscribe({
      next: async (response: any) => {
        const ticket = response.ticket;
        const sessionId = `quick_${Date.now()}`;
        
        const serverUrl = this.getWsServerUrl();
        const wsUrl = `${serverUrl}/api/ws/ssh/0?ticket=${ticket}`;
        
        const ws = new WebSocket(wsUrl);
        
        ws.onopen = () => {
          // Send connection details
          ws.send(JSON.stringify({
            type: 'connect',
            host: data.host,
            port: parseInt(data.port) || 22,
            username: data.username,
            password: data.password,
            auth_type: 'password'
          }));
          
          loading.dismiss();
          const session: TerminalSession = {
            id: sessionId,
            hostId: 0,
            hostName: `${data.username}@${data.host}`,
            ws: ws,
            connected: true
          };
          this.sessions.push(session);
          this.activeSessionId = sessionId;
        };

        ws.onclose = () => {
          const session = this.sessions.find(s => s.id === sessionId);
          if (session) {
            session.connected = false;
          }
        };

        ws.onerror = async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('terminal.connectionFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        };
      },
      error: async () => {
        loading.dismiss();
        const toast = await this.toastController.create({
          message: await this.translate.get('terminal.connectionFailed').toPromise(),
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }

  // Terminal control methods
  async reconnect() {
    const session = this.activeSession;
    if (session && !session.connected) {
      // Close and cleanup existing session
      this.closeSession(session.id);
      
      // Find host and reconnect
      const host = this.hosts.find(h => h.id === session.hostId);
      if (host) {
        await this.connectToHost(host);
      }
    }
  }

  disconnect() {
    const session = this.activeSession;
    if (session) {
      if (session.ws) {
        session.ws.close();
      }
      session.connected = false;
    }
  }

  toggleSftp() {
    this.showSftp = !this.showSftp;
    // TODO: Implement SFTP browser
    this.toastController.create({
      message: 'SFTP browser coming soon',
      duration: 2000
    }).then(t => t.present());
  }

  async showQuickCommands() {
    // Load command templates
    const alert = await this.alertController.create({
      header: await this.translate.get('terminal.commands').toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' }
      ]
    });
    await alert.present();
  }

  // Keyboard toolbar methods
  toggleKeyboardToolbar() {
    this.showKeyboardToolbar = !this.showKeyboardToolbar;
  }

  toggleModifier(key: 'ctrl' | 'alt' | 'shift') {
    this.modifiers[key] = !this.modifiers[key];
  }

  clearModifiers() {
    this.modifiers.ctrl = false;
    this.modifiers.alt = false;
    this.modifiers.shift = false;
  }

  sendKey(key: string) {
    const session = this.activeSession;
    if (!session?.terminal || !session?.ws) return;

    let data = '';
    switch (key) {
      case 'Escape':
        data = '\x1b';
        break;
      case 'Tab':
        data = '\t';
        break;
      case 'ArrowUp':
        data = '\x1b[A';
        break;
      case 'ArrowDown':
        data = '\x1b[B';
        break;
      case 'ArrowRight':
        data = '\x1b[C';
        break;
      case 'ArrowLeft':
        data = '\x1b[D';
        break;
      default:
        data = key;
    }

    // Apply modifiers
    if (this.modifiers.ctrl && data.length === 1) {
      const charCode = data.toUpperCase().charCodeAt(0);
      if (charCode >= 65 && charCode <= 90) {
        data = String.fromCharCode(charCode - 64);
      }
    }

    // Send via WebSocket
    if (session.ws.readyState === WebSocket.OPEN) {
      session.ws.send(JSON.stringify({ type: 'input', data }));
    }

    this.clearModifiers();
  }

  sendCtrlKey(char: string) {
    const session = this.activeSession;
    if (!session?.ws) return;

    const charCode = char.toUpperCase().charCodeAt(0);
    if (charCode >= 65 && charCode <= 90) {
      const data = String.fromCharCode(charCode - 64);
      if (session.ws.readyState === WebSocket.OPEN) {
        session.ws.send(JSON.stringify({ type: 'input', data }));
      }
    }
  }

  sendChar(char: string) {
    const session = this.activeSession;
    if (!session?.ws) return;

    if (session.ws.readyState === WebSocket.OPEN) {
      session.ws.send(JSON.stringify({ type: 'input', data: char }));
    }
  }

  async copySelection() {
    const session = this.activeSession;
    if (!session?.terminal) return;

    const selection = session.terminal.getSelection();
    if (selection) {
      await navigator.clipboard.writeText(selection);
      const toast = await this.toastController.create({
        message: 'Copied to clipboard',
        duration: 1500,
        color: 'success'
      });
      toast.present();
    }
  }

  async pasteFromClipboard() {
    const session = this.activeSession;
    if (!session?.ws) return;

    try {
      const text = await navigator.clipboard.readText();
      if (text && session.ws.readyState === WebSocket.OPEN) {
        session.ws.send(JSON.stringify({ type: 'input', data: text }));
      }
    } catch (err) {
      const toast = await this.toastController.create({
        message: 'Failed to paste from clipboard',
        duration: 2000,
        color: 'danger'
      });
      toast.present();
    }
  }

  updateTerminalSize(cols: number, rows: number) {
    this.terminalSize = `${cols}x${rows}`;
  }
}
