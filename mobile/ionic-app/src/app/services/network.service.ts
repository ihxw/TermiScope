import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import { NetworkTemplate, NetworkTask, NetworkTaskStats } from '../models';

@Injectable({
  providedIn: 'root'
})
export class NetworkService {
  constructor(private api: ApiService) {}

  // Network Templates - 路径与 Web 端一致: /monitor/network/templates
  getTemplates(): Observable<NetworkTemplate[]> {
    return this.api.get<NetworkTemplate[]>('/monitor/network/templates');
  }

  createTemplate(template: Partial<NetworkTemplate>): Observable<NetworkTemplate> {
    return this.api.post<NetworkTemplate>('/monitor/network/templates', template);
  }

  updateTemplate(id: number, template: Partial<NetworkTemplate>): Observable<NetworkTemplate> {
    return this.api.put<NetworkTemplate>(`/monitor/network/templates/${id}`, template);
  }

  deleteTemplate(id: number): Observable<any> {
    return this.api.delete(`/monitor/network/templates/${id}`);
  }

  // Web 端使用 /monitor/network/apply-template
  batchApplyTemplate(data: { template_id: number; host_ids: number[] }): Observable<any> {
    return this.api.post('/monitor/network/apply-template', data);
  }

  getTemplateAssignments(id: number): Observable<any> {
    return this.api.get(`/monitor/network/templates/${id}/assignments`);
  }

  // Network Tasks (Latency Monitoring)
  getNetworkTasks(hostId: number): Observable<NetworkTask[]> {
    return this.api.get<NetworkTask[]>(`/ssh-hosts/${hostId}/network/tasks`);
  }

  createNetworkTask(data: Partial<NetworkTask>): Observable<NetworkTask> {
    return this.api.post<NetworkTask>('/monitor/network/tasks', data);
  }

  updateNetworkTask(id: number, data: Partial<NetworkTask>): Observable<NetworkTask> {
    return this.api.put<NetworkTask>(`/monitor/network/tasks/${id}`, data);
  }

  deleteNetworkTask(id: number): Observable<any> {
    return this.api.delete(`/monitor/network/tasks/${id}`);
  }

  getTaskStats(taskId: number, range: string = '24h'): Observable<NetworkTaskStats> {
    return this.api.get<NetworkTaskStats>(`/monitor/network/stats/${taskId}?range=${range}`);
  }
}
