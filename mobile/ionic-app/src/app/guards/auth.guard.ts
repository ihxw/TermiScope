import { Injectable } from '@angular/core';
import { CanActivate, Router, ActivatedRouteSnapshot, RouterStateSnapshot } from '@angular/router';
import { AuthStore } from '../stores/auth.store';

@Injectable({
  providedIn: 'root'
})
export class AuthGuard implements CanActivate {
  constructor(
    private authStore: AuthStore,
    private router: Router
  ) {}

  canActivate(route: ActivatedRouteSnapshot, state: RouterStateSnapshot): boolean {
    if (this.authStore.isAuthenticated) {
      // Check admin requirement
      if (route.data['requiresAdmin'] && !this.authStore.isAdmin) {
        this.router.navigate(['/dashboard/monitor']);
        return false;
      }
      return true;
    }

    // Not authenticated, redirect to login
    this.router.navigate(['/login'], { queryParams: { redirect: state.url } });
    return false;
  }
}

@Injectable({
  providedIn: 'root'
})
export class PublicGuard implements CanActivate {
  constructor(
    private authStore: AuthStore,
    private router: Router
  ) {}

  canActivate(route: ActivatedRouteSnapshot): boolean {
    // If already authenticated, go to dashboard
    if (this.authStore.isAuthenticated) {
      this.router.navigate(['/dashboard/monitor']);
      return false;
    }
    return true;
  }
}

@Injectable({
  providedIn: 'root'
})
export class InitGuard implements CanActivate {
  constructor(
    private authStore: AuthStore,
    private router: Router
  ) {}

  async canActivate(route: ActivatedRouteSnapshot): Promise<boolean> {
    // If authenticated, go to dashboard
    if (this.authStore.isAuthenticated) {
      this.router.navigate(['/dashboard/monitor']);
      return false;
    }
    return true;
  }
}
