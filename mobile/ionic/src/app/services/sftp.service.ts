import { Injectable } from '@angular/core';
import { ApiService } from './api.service';

export interface FileEntry {
    name: string;
    size: number;
    mode: string;
    mod_time: string;
    is_dir: boolean;
    path: string;
}

@Injectable({
    providedIn: 'root'
})
export class SftpService {

    constructor(private api: ApiService) { }

    listFiles(hostId: string | number, path: string = '.') {
        return this.api.get<FileEntry[]>(`/sftp/list/${hostId}`, { path });
    }

    downloadFile(hostId: string | number, path: string) {
        // For download, we might need to handle blob/stream. 
        // Usually browser handles link clicks, but for secure API we might need a signed URL or blob download.
        // Let's assume for now we use the API service but might need specific response type.
        // Or we can construct a URL if it uses token in query (backend supports it?). 
        // Checking backend... usually we use a specific download method.
        // Backend `sftpHandler.Download` seems to stream file.
        return this.api.get(`/sftp/download/${hostId}`, { path }, { responseType: 'blob' });
    }

    deleteFile(hostId: string | number, path: string) {
        return this.api.delete(`/sftp/delete/${hostId}`, { params: { path } });
    }

    createDirectory(hostId: string | number, path: string) {
        return this.api.post(`/sftp/mkdir/${hostId}`, { path });
    }

    rename(hostId: string | number, oldPath: string, newPath: string) {
        return this.api.post(`/sftp/rename/${hostId}`, { old_path: oldPath, new_path: newPath });
    }

    upload(hostId: string | number, path: string, file: File) {
        const formData = new FormData();
        formData.append('file', file);
        formData.append('path', path);
        return this.api.post(`/sftp/upload/${hostId}`, formData, {
            headers: { 'Content-Type': 'multipart/form-data' }
        });
    }
}
