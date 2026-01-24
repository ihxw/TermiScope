import { Injectable } from '@angular/core';
import { ApiService } from './api.service';
import { BehaviorSubject } from 'rxjs';

export interface Host {
    id: number;
    name: string;
    host: string;
    port: number;
    username: string;
    group_name?: string;
    description?: string;
    host_type?: string;
    monitor_enabled: boolean;
    os?: string;
    uptime?: number;
    cpu?: number;
    mem_used?: number;
    mem_total?: number;
    disk_used?: number;
    disk_total?: number;
    net_rx?: number;
    net_tx?: number;
    net_rx_rate?: number;
    net_tx_rate?: number;
    last_updated?: number;
    agent_version?: string;
    // ... other metrics
}

@Injectable({
    providedIn: 'root'
})
export class HostService {
    private hostsSubject = new BehaviorSubject<Host[]>([]);
    public hosts$ = this.hostsSubject.asObservable();

    private socket: WebSocket | null = null;
    private connected = false;

    constructor(private api: ApiService) { }

    async fetchHosts() {
        try {
            const data: Host[] = await this.api.get('/ssh-hosts');
            this.updateHostsList(data);
            return data;
        } catch (error) {
            console.error('Failed to fetch hosts', error);
            throw error;
        }
    }

    private updateHostsList(newHosts: Host[]) {
        this.hostsSubject.next(newHosts);
    }

    async connectToMonitor() {
        try {
            const res: any = await this.api.post('/auth/ws-ticket');
            const ticket = res.ticket;

            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
            // Use saved server URL if available, otherwise fallback to current host
            const savedUrl = localStorage.getItem('server_url');
            let wsHost = '';
            let wsProtocol = protocol;

            if (savedUrl) {
                // Parse the URL to get host and protocol
                const url = new URL(savedUrl);
                wsHost = url.host;
                wsProtocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
            } else {
                wsHost = window.location.host || 'localhost:8080';
            }

            const wsUrl = `${wsProtocol}//${wsHost}/api/monitor/stream?token=${ticket}`;

            this.socket = new WebSocket(wsUrl);

            this.socket.onopen = () => {
                this.connected = true;
                console.log('Monitor WS Connected');
            };

            this.socket.onmessage = (event) => {
                try {
                    const msg = JSON.parse(event.data);
                    if (msg.type === 'init' || msg.type === 'update') {
                        this.handleUpdate(msg.data);
                    }
                } catch (e) {
                    console.error(e);
                }
            };

            this.socket.onclose = () => {
                this.connected = false;
                // Reconnect logic could go here
            };

        } catch (e) {
            console.error('Failed to connect to monitor', e);
        }
    }

    private handleUpdate(updates: any[]) {
        const currentHosts = this.hostsSubject.value;
        const newHosts = [...currentHosts];

        updates.forEach(update => {
            const index = newHosts.findIndex(h => h.id === update.host_id);
            if (index !== -1) {
                newHosts[index] = { ...newHosts[index], ...update };
            }
        });

        this.hostsSubject.next(newHosts);
    }

    async addHost(hostData: any) {
        return this.api.post('/ssh-hosts', hostData).then(async () => {
            await this.fetchHosts();
        });
    }

    async updateHost(id: number, hostData: any) {
        return this.api.put(`/ssh-hosts/${id}`, hostData).then(async () => {
            await this.fetchHosts();
        });
    }

    async deleteHost(id: number) {
        return this.api.delete(`/ssh-hosts/${id}`).then(async () => {
            await this.fetchHosts();
        });
    }

    disconnect() {
        if (this.socket) {
            this.socket.close();
            this.socket = null;
        }
    }
}
