import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import { User } from '../models';

@Injectable({
  providedIn: 'root'
})
export class UserService {
  constructor(private api: ApiService) {}

  getUsers(page: number = 1, pageSize: number = 20): Observable<any> {
    return this.api.get(`/users?page=${page}&page_size=${pageSize}`);
  }

  getUser(id: number): Observable<User> {
    return this.api.get<User>(`/users/${id}`);
  }

  createUser(user: Partial<User> & { password: string }): Observable<User> {
    return this.api.post<User>('/users', user);
  }

  updateUser(id: number, user: Partial<User>): Observable<User> {
    return this.api.put<User>(`/users/${id}`, user);
  }

  deleteUser(id: number): Observable<any> {
    return this.api.delete(`/users/${id}`);
  }

  resetPassword(id: number): Observable<{ temp_password: string }> {
    return this.api.post<{ temp_password: string }>(`/users/${id}/reset-password`, {});
  }

  toggleUserStatus(id: number, isActive: boolean): Observable<User> {
    return this.api.put<User>(`/users/${id}/status`, { is_active: isActive });
  }
}
