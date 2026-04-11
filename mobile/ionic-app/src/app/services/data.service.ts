import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import { ConnectionLog, Command, Recording, SFTPFile } from '../models';

@Injectable({
  providedIn: 'root'
})
export class ConnectionLogService {
  constructor(private api: ApiService) {}

  getLogs(page: number = 1, pageSize: number = 20, hostId?: number): Observable<any> {
    let url = `/connection-logs?page=${page}&page_size=${pageSize}`;
    if (hostId) url += `&host_id=${hostId}`;
    return this.api.get(url);
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

  getCommands(page: number = 1, pageSize: number = 20): Observable<any> {
    return this.api.get(`/commands?page=${page}&page_size=${pageSize}`);
  }

  getCommand(id: number): Observable<Command> {
    return this.api.get<Command>(`/commands/${id}`);
  }

  createCommand(command: Partial<Command>): Observable<Command> {
    return this.api.post<Command>('/commands', command);
  }

  updateCommand(id: number, command: Partial<Command>): Observable<Command> {
    return this.api.put<Command>(`/commands/${id}`, command);
  }

  deleteCommand(id: number): Observable<any> {
    return this.api.delete(`/commands/${id}`);
  }

  executeCommand(hostId: number, commandId: number): Observable<any> {
    return this.api.post(`/ssh-hosts/${hostId}/execute`, { command_id: commandId });
  }
}

@Injectable({
  providedIn: 'root'
})
export class RecordingService {
  constructor(private api: ApiService) {}

  getRecordings(page: number = 1, pageSize: number = 20): Observable<any> {
    return this.api.get(`/recordings?page=${page}&page_size=${pageSize}`);
  }

  getRecording(id: number): Observable<Recording> {
    return this.api.get<Recording>(`/recordings/${id}`);
  }

  deleteRecording(id: number): Observable<any> {
    return this.api.delete(`/recordings/${id}`);
  }

  getRecordingStreamUrl(sessionId: string): string {
    return `${this.api.getServerUrl()}/api/recordings/${sessionId}/stream`;
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
