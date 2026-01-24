import { Injectable } from '@angular/core';
import { ApiService } from './api.service';

export interface NetworkTask {
    id: number;
    user_id: number;
    host_id: number;
    name: string;
    target: string;
    type: string; // ping, tcp, http
    interval: number;
    timeout: number;
    is_active: boolean;
    created_at: string;
    host_name?: string; // If backend joins it
}

export interface NetworkStats {
    task_id: number;
    latency_ms: number;
    packet_loss: number;
    status_code: number; // for http
    success: boolean;
    error_message: string;
    created_at: string;
}

@Injectable({
    providedIn: 'root'
})
export class NetworkService {

    constructor(private api: ApiService) { }

    async listTasks() {
        try {
            const hosts = await this.api.get<any[]>('/ssh-hosts');
            if (!Array.isArray(hosts)) return [];

            const promises = hosts.map(host =>
                this.getHostTasks(host.id).then((res: any) => {
                    const tasks = res.tasks || res;
                    return Array.isArray(tasks) ? tasks.map((t: any) => ({ ...t, host_name: host.name })) : [];
                }).catch(() => [])
            );

            const results = await Promise.all(promises);

            // Manual flattening to avoid TS reduce/flat issues
            const allTasks: any[] = [];
            results.forEach((r: any) => {
                if (Array.isArray(r)) {
                    allTasks.push(...r);
                }
            });
            return allTasks;
        } catch (e) {
            console.error('Failed to list tasks', e);
            return [];
        }
    }

    getHostTasks(hostId: string | number) {
        return this.api.get<any>(`/ssh-hosts/${hostId}/network/tasks`);
    }

    createTask(task: any) {
        return this.api.post('/monitor/network/tasks', task);
    }

    updateTask(id: number | string, task: any) {
        return this.api.put(`/monitor/network/tasks/${id}`, task);
    }

    deleteTask(id: number | string) {
        return this.api.delete(`/monitor/network/tasks/${id}`);
    }

    getStats(taskId: number | string, limit: number = 50) {
        return this.api.get<NetworkStats[]>(`/monitor/network/stats/${taskId}`, { limit });
    }

    // Templates
    listTemplates() {
        return this.api.get('/monitor/network/templates');
    }
}
