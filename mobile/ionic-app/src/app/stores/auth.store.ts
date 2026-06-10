import { Injectable } from '@angular/core';
import { BehaviorSubject, Observable } from 'rxjs';
import { AuthService } from '../services/auth.service';
import { User, LoginResponse } from '../models';

@Injectable({
  providedIn: 'root'
})
export class AuthStore {
  private userSubject = new BehaviorSubject<User | null>(null);
  private tokenSubject = new BehaviorSubject<string | null>(localStorage.getItem('token'));
  private refreshTokenSubject = new BehaviorSubject<string | null>(localStorage.getItem('refresh_token'));

  user$ = this.userSubject.asObservable();
  token$ = this.tokenSubject.asObservable();
  refreshToken$ = this.refreshTokenSubject.asObservable();

  constructor(private authService: AuthService) {
    // Try to restore user on init
    if (this.isAuthenticated) {
      this.fetchCurrentUser().subscribe({
        error: () => this.clearAuth()
      });
    }
  }

  get user(): User | null {
    return this.userSubject.value;
  }

  get token(): string | null {
    return this.tokenSubject.value;
  }

  get refreshToken(): string | null {
    return this.refreshTokenSubject.value;
  }

  get isAuthenticated(): boolean {
    return !!this.tokenSubject.value;
  }

  get isAdmin(): boolean {
    return this.user?.role === 'admin';
  }

  login(username: string, password: string, remember: boolean = false): Observable<LoginResponse> {
    return new Observable(observer => {
      this.authService.login(username, password, remember).subscribe({
        next: (response) => {
          this.setAuth(response);
          observer.next(response);
          observer.complete();
        },
        error: (error) => observer.error(error)
      });
    });
  }

  verify2FA(userId: number, code: string, token: string): Observable<LoginResponse> {
    return new Observable(observer => {
      this.authService.verify2FALogin(userId, code, token).subscribe({
        next: (response) => {
          this.setAuth(response);
          observer.next(response);
          observer.complete();
        },
        error: (error) => observer.error(error)
      });
    });
  }

  logout(): Observable<any> {
    return new Observable(observer => {
      this.authService.logout().subscribe({
        next: () => {
          this.clearAuth();
          observer.next(null);
          observer.complete();
        },
        error: (error) => {
          this.clearAuth();
          observer.error(error);
        }
      });
    });
  }

  fetchCurrentUser(): Observable<User> {
    return new Observable(observer => {
      this.authService.getCurrentUser().subscribe({
        next: (user) => {
          this.userSubject.next(user);
          observer.next(user);
          observer.complete();
        },
        error: (error) => observer.error(error)
      });
    });
  }

  setAuth(response: LoginResponse): void {
    this.tokenSubject.next(response.token);
    this.refreshTokenSubject.next(response.refresh_token);
    this.userSubject.next(response.user);

    localStorage.setItem('token', response.token);
    if (response.refresh_token) {
      localStorage.setItem('refresh_token', response.refresh_token);
    }
  }

  setToken(token: string): void {
    this.tokenSubject.next(token);
    localStorage.setItem('token', token);
  }

  setRefreshToken(token: string): void {
    this.refreshTokenSubject.next(token);
    localStorage.setItem('refresh_token', token);
  }

  setUser(user: User): void {
    this.userSubject.next(user);
  }

  clearAuth(): void {
    this.userSubject.next(null);
    this.tokenSubject.next(null);
    this.refreshTokenSubject.next(null);
    localStorage.removeItem('token');
    localStorage.removeItem('refresh_token');
  }
}
