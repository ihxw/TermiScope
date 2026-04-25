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

/**
 * Calculates character cell dimensions from a rendered xterm.js terminal.
 */
function getCharSize(terminal: Terminal): { w: number; h: number } | null {
  const screen = (terminal as any).element?.querySelector('.xterm-screen') as HTMLElement | null;
  if (!screen) return null;
  const cols = terminal.cols;
  const rows = terminal.rows;
  if (!cols || !rows) return null;
  return {
    w: screen.clientWidth / cols,
    h: screen.clientHeight / rows,
  };
}

/**
 * Button-triggered selection mode for xterm.js on mobile.
 * When active, intercepts touch events on the terminal to let the user
 * tap-and-drag to select text, similar to mobile file picker.
 */
class SelectionMode {
  private container: HTMLElement;
  private terminal: Terminal;
  private overlay: HTMLElement | null = null;
  private toolbar: HTMLElement | null = null;
  private anchor: { col: number; row: number } | null = null;
  private charSize: { w: number; h: number } | null = null;
  private isActive = false;
  private isDragging = false;
  private onCopy: (text: string) => void;
  private onExit: () => void;

  constructor(
    container: HTMLElement,
    terminal: Terminal,
    onCopy: (text: string) => void,
    onExit: () => void
  ) {
    this.container = container;
    this.terminal = terminal;
    this.onCopy = onCopy;
    this.onExit = onExit;
  }

  /** Activate selection mode — creates overlay and binds listeners */
  start() {
    if (this.isActive) return;
    this.isActive = true;
    this.terminal.clearSelection();

    // Create semi-transparent overlay that captures touch events
    this.overlay = document.createElement('div');
    this.overlay.className = 'selection-overlay';
    this.overlay.addEventListener('touchstart', this.onTouchStart, { passive: false });
    this.overlay.addEventListener('touchmove', this.onTouchMove, { passive: false });
    this.overlay.addEventListener('touchend', this.onTouchEnd);

    // Create toolbar at the bottom with Done / Select All buttons
    this.toolbar = document.createElement('div');
    this.toolbar.className = 'selection-toolbar';
    this.toolbar.innerHTML = `
      <button class="sel-btn sel-cancel">${this.getTrans('common.cancel')}</button>
      <span class="sel-preview"></span>
      <button class="sel-btn sel-all">${this.getTrans('terminal.selectAll')}</button>
      <button class="sel-btn sel-done">${this.getTrans('terminal.done')}</button>
    `;
    // Cancel button
    (this.toolbar.querySelector('.sel-cancel') as HTMLElement).addEventListener('click', () => this.exit());
    // Select All button
    (this.toolbar.querySelector('.sel-all') as HTMLElement).addEventListener('click', () => {
      const cols = this.terminal.cols;
      const rows = this.terminal.rows;
      this.terminal.select(0, 0, cols * rows);
      this.updatePreview();
    });
    // Done button
    (this.toolbar.querySelector('.sel-done') as HTMLElement).addEventListener('click', () => {
      const text = this.terminal.getSelection();
      if (text) {
        this.onCopy(text);
      }
      this.exit();
    });

    this.container.appendChild(this.overlay);
    this.container.appendChild(this.toolbar);
  }

  private exit() {
    this.isActive = false;
    this.isDragging = false;
    this.anchor = null;
    if (this.overlay) {
      this.overlay.remove();
      this.overlay = null;
    }
    if (this.toolbar) {
      this.toolbar.remove();
      this.toolbar = null;
    }
    this.onExit();
  }

  private getTrans(key: string): string {
    // Minimal translation fallback — keys are in en-US/zh-CN
    const map: Record<string, Record<string, string>> = {
      'en': {
        'common.cancel': 'Cancel',
        'terminal.selectAll': 'Select All',
        'terminal.done': 'Done',
      },
      'zh': {
        'common.cancel': '取消',
        'terminal.selectAll': '全选',
        'terminal.done': '完成',
      }
    };
    const lang = navigator.language.startsWith('zh') ? 'zh' : 'en';
    return map[lang][key] || key;
  }

  private getCellFromTouch(e: TouchEvent): { col: number; row: number } | null {
    if (!this.charSize || e.touches.length !== 1) return null;
    const rect = this.container.getBoundingClientRect();
    const x = Math.max(0, e.touches[0].clientX - rect.left);
    const y = Math.max(0, e.touches[0].clientY - rect.top);
    const col = Math.min(this.terminal.cols - 1, Math.floor(x / this.charSize.w));
    const row = Math.min(this.terminal.rows - 1, Math.floor(y / this.charSize.h));
    return { col, row };
  }

  private onTouchStart = (e: TouchEvent) => {
    e.preventDefault();
    this.isDragging = true;
    this.charSize = getCharSize(this.terminal);
    const cell = this.getCellFromTouch(e);
    if (cell) {
      this.anchor = cell;
      this.terminal.select(cell.col, cell.row, 1);
    }
  };

  private onTouchMove = (e: TouchEvent) => {
    e.preventDefault();
    if (!this.isDragging || !this.anchor) return;
    const cell = this.getCellFromTouch(e);
    if (!cell) return;

    const { col: startCol, row: startRow } = this.anchor;
    const startPos = startRow * this.terminal.cols + startCol;
    const endPos = cell.row * this.terminal.cols + cell.col;

    if (endPos >= startPos) {
      this.terminal.select(startCol, startRow, endPos - startPos + 1);
    } else {
      this.terminal.select(cell.col, cell.row, startPos - endPos + 1);
    }
    this.updatePreview();
  };

  private onTouchEnd = () => {
    this.isDragging = false;
    this.updatePreview();
  };

  private updatePreview() {
    const text = this.terminal.getSelection();
    const preview = this.toolbar?.querySelector('.sel-preview') as HTMLElement | null;
    if (preview) {
      preview.textContent = text ? text.substring(0, 50) + (text.length > 50 ? '…' : '') : '';
    }
  }

  dispose() {
    this.exit();
  }
}

interface TerminalSession {
  id: string;
  hostId: number;
  hostName: string;
  ws?: WebSocket;
  connected: boolean;
  terminal?: Terminal;
  fitAddon?: FitAddon;
  container?: HTMLElement;
  selectionMode?: SelectionMode;
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
  selectionModeActive = false;
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
      if (session.selectionMode) {
        session.selectionMode.dispose();
      }
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
          allowProposedApi: true,
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

    // Clean up any previous selection mode
    if (session.selectionMode) {
      session.selectionMode.dispose();
    }
    this.selectionModeActive = false;

    session.terminal.open(container);
    session.container = container;

    // Initialize selection mode handler (button-triggered, not long-press)
    session.selectionMode = new SelectionMode(
      container,
      session.terminal,
      (text: string) => this.copyText(text),
      () => { this.selectionModeActive = false; }
    );

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
      if (session.selectionMode) {
        session.selectionMode.dispose();
      }
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
      await this.copyText(selection);
    }
  }

  async copyText(text: string) {
    await navigator.clipboard.writeText(text);
    const toast = await this.toastController.create({
      message: await this.translate.get('terminal.copied').toPromise() || '已复制到剪贴板',
      duration: 1500,
      color: 'success'
    });
    toast.present();
  }

  /** Toggle selection mode — button-triggered, not long-press */
  toggleSelectionMode() {
    const session = this.activeSession;
    if (!session?.selectionMode) return;

    if (this.selectionModeActive) {
      // Exit selection mode
      session.selectionMode.dispose();
      this.selectionModeActive = false;
    } else {
      // Enter selection mode
      session.selectionMode.start();
      this.selectionModeActive = true;
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

  selectAll() {
    const session = this.activeSession;
    if (!session?.terminal) return;
    const rows = session.terminal.rows;
    const cols = session.terminal.cols;
    // Select the visible portion of the terminal buffer
    session.terminal.select(0, 0, cols * rows);
    session.terminal.focus();
  }

  updateTerminalSize(cols: number, rows: number) {
    this.terminalSize = `${cols}x${rows}`;
  }
}
