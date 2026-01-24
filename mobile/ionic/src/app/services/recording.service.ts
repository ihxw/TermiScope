import { Injectable } from '@angular/core';
import { ApiService } from './api.service';

@Injectable({
    providedIn: 'root'
})
export class RecordingService {

    constructor(private api: ApiService) { }

    list() {
        return this.api.get<any[]>('/recordings');
    }

    delete(id: number | string) {
        return this.api.delete(`/recordings/${id}`);
    }

    getStream(id: number | string) {
        // Returns text (NDJSON)
        return this.api.get(`/recordings/${id}/stream`, {}, { responseType: 'text' });
    }
}
