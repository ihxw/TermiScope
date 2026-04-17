import { Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse, HttpHeaders } from '@angular/common/http';
import { BehaviorSubject, Observable, throwError } from 'rxjs';
import { catchError, map, switchMap, filter, take } from 'rxjs/operators';
import { Storage } from '@ionic/storage-angular';
import { environment } from '../../environments/environment';
import { ApiResponse, LoginResponse } from '../models';

@Injectable({
  providedIn: 'root'
})
export class ApiService {
  private baseUrl: string = '';
  private serverUrl: string = '';
  private isRefreshing = false;
  private refreshTokenSubject: BehaviorSubject<string | null> = new BehaviorSubject<string | null>(null);

  constructor(
    private http: HttpClient,
    private storage: Storage
  ) {
    this.initStorage();
  }

  private async initStorage() {
    await this.storage.create();
    const savedUrl = await this.storage.get('serverUrl');
    this.serverUrl = savedUrl || environment.defaultServerUrl;
  }

  setServerUrl(url: string) {
    this.serverUrl = url.replace(/\/$/, '');
    this.storage.set('serverUrl', this.serverUrl);
  }

  getServerUrl(): string {
    return this.serverUrl;
  }

  getFullUrl(path: string): string {
    const base = this.serverUrl || '';
    return `${base}${environment.apiBaseUrl}${path}`;
  }

  get<T>(path: string, options: any = {}): Observable<T> {
    return this.http.get(this.getFullUrl(path), { ...this.getOptions(options), observe: 'body' }).pipe(
      map((response: any) => this.handleResponse<T>(response)),
      catchError((error: HttpErrorResponse) => this.handleError(error, () => this.get<T>(path, options)))
    );
  }

  post<T>(path: string, body: any = {}, options: any = {}): Observable<T> {
    return this.http.post(this.getFullUrl(path), body, { ...this.getOptions(options), observe: 'body' }).pipe(
      map((response: any) => this.handleResponse<T>(response)),
      catchError((error: HttpErrorResponse) => this.handleError(error, () => this.post<T>(path, body, options)))
    );
  }

  put<T>(path: string, body: any = {}, options: any = {}): Observable<T> {
    return this.http.put(this.getFullUrl(path), body, { ...this.getOptions(options), observe: 'body' }).pipe(
      map((response: any) => this.handleResponse<T>(response)),
      catchError((error: HttpErrorResponse) => this.handleError(error, () => this.put<T>(path, body, options)))
    );
  }

  delete<T>(path: string, options: any = {}): Observable<T> {
    return this.http.delete(this.getFullUrl(path), { ...this.getOptions(options), observe: 'body' }).pipe(
      map((response: any) => this.handleResponse<T>(response)),
      catchError((error: HttpErrorResponse) => this.handleError(error, () => this.delete<T>(path, options)))
    );
  }

  private getOptions(options: any = {}): any {
    const token = localStorage.getItem('token');
    const headers: any = {};
    
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    return {
      ...options,
      withCredentials: true,
      headers: new HttpHeaders({ ...headers, ...options.headers })
    };
  }

  private handleResponse<T>(response: any): T {
    // Handle blob responses (file downloads)
    if (response instanceof Blob) {
      return response as T;
    }
    // Handle standard API responses
    if (response && typeof response === 'object' && 'success' in response) {
      if (response.success) {
        return response.data;
      }
      throw new Error(response.error || 'Request failed');
    }
    // Return raw response for non-standard responses
    return response as T;
  }

  private handleError(error: HttpErrorResponse, retryCallback: () => Observable<any>): Observable<any> {
    // Silent error - skip global handling
    if ((error.error as any)?.config?._silentError) {
      return throwError(() => error);
    }

    if (error.status === 401) {
      const url = error.url || '';
      
      // Skip refresh for login/refresh endpoints
      if (url.includes('/auth/login') || url.includes('/auth/refresh')) {
        this.clearAuth();
        return throwError(() => error);
      }

      return this.handle401Error(retryCallback);
    }

    return throwError(() => error);
  }

  private handle401Error(retryCallback: () => Observable<any>): Observable<any> {
    if (!this.isRefreshing) {
      this.isRefreshing = true;
      this.refreshTokenSubject.next(null);

      const refreshToken = localStorage.getItem('refresh_token');
      
      if (refreshToken) {
        return this.http.post<ApiResponse<LoginResponse>>(
          this.getFullUrl('/auth/refresh'),
          { refresh_token: refreshToken }
        ).pipe(
          switchMap(response => {
            this.isRefreshing = false;
            if (response.success) {
              const { token, refresh_token } = response.data;
              localStorage.setItem('token', token);
              if (refresh_token) {
                localStorage.setItem('refresh_token', refresh_token);
              }
              this.refreshTokenSubject.next(token);
              return retryCallback();
            }
            throw new Error('Refresh failed');
          }),
          catchError(err => {
            this.isRefreshing = false;
            this.clearAuth();
            return throwError(() => err);
          })
        );
      } else {
        this.isRefreshing = false;
        this.clearAuth();
        return throwError(() => new Error('No refresh token'));
      }
    } else {
      // Wait for refresh to complete
      return this.refreshTokenSubject.pipe(
        filter(token => token !== null),
        take(1),
        switchMap(() => retryCallback())
      );
    }
  }

  private clearAuth() {
    localStorage.removeItem('token');
    localStorage.removeItem('refresh_token');
  }
}
