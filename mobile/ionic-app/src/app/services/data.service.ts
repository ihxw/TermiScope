import { Injectable } from '@angular/core';
import { Observable, from, switchMap } from 'rxjs';
import { ApiService } from './api.service';
import { AuthService } from './auth.service';
import { ConnectionLog, Command, Recording, SFTPFile } from '../models';

@Injectable({
  providedIn: 'root'
})
export class ConnectionLogService {
  constructor(private api: ApiService) {}

  getLogs(filters: any = {}): Observable<any> {
    const params = new URLSearchParams(filters).toString();
    return this.api.get(`/connection-logs${params ? '?' + params : ''}`);
  }

  getLog(id: number): Observable<ConnectionLog> {
    return this.api.get<ConnectionLog>(`/connection-logs/${id}`);
  }
}

@Injectable({
  providedIn: 'root'
})
export class CommandService {
  constructor(private api: ApiService) {}

  // Web 端使用 /command-templates，无分页
  getCommands(): Observable<any> {
    return this.api.get('/command-templates');
  }

  getCommand(id: number): Observable<Command> {
    return this.api.get<Command>(`/command-templates/${id}`);
  }

  createCommand(command: Partial<Command>): Observable<Command> {
    return this.api.post<Command>('/command-templates', command);
  }

  updateCommand(id: number, command: Partial<Command>): Observable<Command> {
    return this.api.put<Command>(`/command-templates/${id}`, command);
  }

  deleteCommand(id: number): Observable<any> {
    return this.api.delete(`/command-templates/${id}`);
  }

  // Note: Web 端没有 executeCommand 功能，命令模板仅在终端中手动使用
  // 服务端不存在 /ssh-hosts/:id/execute 路由
}

@Injectable({
  providedIn: 'root'
})
export class RecordingService {
  constructor(
    private api: ApiService,
    private authService: AuthService
  ) {}

  // Web 端使用 GET /recordings 无分页参数
  getRecordings(): Observable<any> {
    return this.api.get('/recordings');
  }

  getRecording(id: number): Observable<Recording> {
    return this.api.get<Recording>(`/recordings/${id}`);
  }

  deleteRecording(id: number): Observable<any> {
    return this.api.delete(`/recordings/${id}`);
  }

  // Web 端先获取 ws-ticket，然后拼接带 token 的 URL
  getRecordingStreamUrl(id: number): Observable<string> {
    return this.authService.getWSTicket().pipe(
      switchMap((res: any) => {
        const serverUrl = this.api.getServerUrl();
        const url = `${serverUrl}/api/recordings/${id}/stream?token=${res.ticket}`;
        return new Observable<string>(observer => {
          observer.next(url);
          observer.complete();
        });
      })
    );
  }
}

@Injectable({
  providedIn: 'root'
})
export class SFTPService {
  constructor(private api: ApiService) {}

  listFiles(hostId: number, path: string = '.'): Observable<SFTPFile[]> {
    return this.api.get<SFTPFile[]>(`/sftp/list/${hostId}?path=${encodeURIComponent(path)}`);
  }

  downloadFile(hostId: number, path: string): Observable<Blob> {
    return this.api.get(`/sftp/download/${hostId}?path=${encodeURIComponent(path)}&_t=${Date.now()}`, {
      responseType: 'blob'
    });
  }

  uploadFile(hostId: number, path: string, file: File): Observable<any> {
    const formData = new FormData();
    formData.append('path', path);
    formData.append('file', file);
    return this.api.post(`/sftp/upload/${hostId}`, formData);
  }

  deleteFile(hostId: number, path: string): Observable<any> {
    return this.api.delete(`/sftp/delete/${hostId}?path=${encodeURIComponent(path)}`);
  }

  renameFile(hostId: number, oldPath: string, newPath: string): Observable<any> {
    return this.api.post(`/sftp/rename/${hostId}`, { old_path: oldPath, new_path: newPath });
  }

  pasteFile(hostId: number, source: string, dest: string, type: 'copy' | 'cut'): Observable<any> {
    return this.api.post(`/sftp/paste/${hostId}`, { source, dest, type });
  }

  createDirectory(hostId: number, path: string): Observable<any> {
    return this.api.post(`/sftp/mkdir/${hostId}`, { path });
  }

  createFile(hostId: number, path: string): Observable<any> {
    return this.api.post(`/sftp/create/${hostId}`, { path });
  }

  getDirSize(hostId: number, path: string): Observable<{ size: number } | null> {
    return this.api.get(`/sftp/size/${hostId}?path=${encodeURIComponent(path)}`);
  }

  // Web 端使用 SSE 流式传输，Mobile 端简化为普通 POST
  transferFile(sourceHostId: number, destHostId: number, sourcePath: string, destPath: string, type: 'copy' | 'move' = 'copy'): Observable<any> {
    return this.api.post('/sftp/transfer', {
      source_host_id: String(sourceHostId),
      dest_host_id: String(destHostId),
      source_path: sourcePath,
      dest_path: destPath,
      type: type
    });
  }
}
