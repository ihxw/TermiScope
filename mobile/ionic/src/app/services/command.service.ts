import { Injectable } from '@angular/core';
import { ApiService } from './api.service';

export interface CommandTemplate {
    id: number;
    name: string;
    command: string;
    created_at: string;
}

@Injectable({
    providedIn: 'root'
})
export class CommandService {

    constructor(private api: ApiService) { }

    list() {
        return this.api.get<CommandTemplate[]>('/command-templates');
    }

    create(data: any) {
        return this.api.post('/command-templates', data);
    }

    update(id: number | string, data: any) {
        return this.api.put(`/command-templates/${id}`, data);
    }

    delete(id: number | string) {
        return this.api.delete(`/command-templates/${id}`);
    }
}
