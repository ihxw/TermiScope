import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import { SSHHost, MonitorStatus, NetworkLatency } from '../models';

@Injectable({
  providedIn: 'root'
})
export class SSHService {
  constructor(private api: ApiService) {}

  getHosts(filters: any = {}): Observable<SSHHost[]> {
    const params = new URLSearchParams(filters).toString();
    return this.api.get<SSHHost[]>(`/ssh-hosts${params ? '?' + params : ''}`);
  }

  getHost(id: number, reveal: boolean = false): Observable<SSHHost> {
    const params = reveal ? '?reveal=true' : '';
    return this.api.get<SSHHost>(`/ssh-hosts/${id}${params}`);
  }

  createHost(hostData: Partial<SSHHost>): Observable<SSHHost> {
    return this.api.post<SSHHost>('/ssh-hosts', hostData);
  }

  updateHost(id: number, hostData: Partial<SSHHost>): Observable<SSHHost> {
    return this.api.put<SSHHost>(`/ssh-hosts/${id}`, hostData);
  }

  deleteHost(id: number): Observable<any> {
    return this.api.delete(`/ssh-hosts/${id}`);
  }

  permanentDeleteHost(id: number): Observable<any> {
    return this.api.delete(`/ssh-hosts/${id}/permanent`);
  }

  testConnection(id: number): Observable<any> {
    return this.api.post(`/ssh-hosts/${id}/test`, {});
  }

  deployMonitor(id: number, insecure: boolean = false): Observable<any> {
    return this.api.post(`/ssh-hosts/${id}/monitor/deploy`, { insecure });
  }

  stopMonitor(id: number): Observable<any> {
    return this.api.post(`/ssh-hosts/${id}/monitor/stop`, {});
  }

  updateAgent(id: number): Observable<any> {
    return this.api.post(`/ssh-hosts/${id}/monitor/update`, {});
  }

  updateHostFingerprint(id: number, fingerprint: string): Observable<any> {
    return this.api.put(`/ssh-hosts/${id}/fingerprint`, { fingerprint });
  }

  getMonitorLogs(id: number, page: number = 1, pageSize: number = 20): Observable<any> {
    return this.api.get(`/ssh-hosts/${id}/monitor/logs?page=${page}&page_size=${pageSize}`);
  }

  getTrafficResetLogs(page: number = 1, pageSize: number = 20, hostId: string = ''): Observable<any> {
    let url = `/monitor/traffic-reset-logs?page=${page}&page_size=${pageSize}`;
    if (hostId) url += `&host_id=${hostId}`;
    return this.api.get(url);
  }

  reorderHosts(ids: number[]): Observable<any> {
    return this.api.put('/ssh-hosts/reorder', { device_ids: ids });
  }

  batchDeployMonitor(hostIds: number[], insecure: boolean = false): Observable<any> {
    return this.api.post('/ssh-hosts/monitor/batch-deploy', { host_ids: hostIds, insecure });
  }

  batchStopMonitor(hostIds: number[]): Observable<any> {
    return this.api.post('/ssh-hosts/monitor/batch-stop', { host_ids: hostIds });
  }

  // 注意：监控状态通过 WebSocket /monitor/stream 获取
  // 不再错误地调用 testConnection() 作为 getMonitorStatus()

  getNetworkLatency(hostId: number, limit: number = 100): Observable<NetworkLatency[]> {
    return this.api.get<NetworkLatency[]>(`/monitor/network-latency/${hostId}?limit=${limit}`);
  }

  resetTraffic(hostId: number): Observable<any> {
    return this.api.post(`/monitor/traffic-reset/${hostId}`, {});
  }
}
