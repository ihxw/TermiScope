import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { Storage } from '@ionic/storage-angular';

type Theme = 'light' | 'dark';

@Injectable({
  providedIn: 'root'
})
export class ThemeStore {
  private themeSubject = new BehaviorSubject<Theme>('light');
  theme$ = this.themeSubject.asObservable();

  private storageReady = false;

  constructor(private storage: Storage) {
    this.init();
  }

  private async init() {
    await this.storage.create();
    this.storageReady = true;
    
    const savedTheme = await this.storage.get('theme') as Theme;
    if (savedTheme) {
      this.setTheme(savedTheme);
    } else {
      // Check system preference
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      this.setTheme(prefersDark ? 'dark' : 'light');
    }
  }

  get theme(): Theme {
    return this.themeSubject.value;
  }

  get isDark(): boolean {
    return this.themeSubject.value === 'dark';
  }

  setTheme(theme: Theme): void {
    this.themeSubject.next(theme);
    
    // Apply to document
    document.documentElement.setAttribute('data-theme', theme);
    
    if (this.storageReady) {
      this.storage.set('theme', theme);
    }
  }

  toggleTheme(): void {
    const newTheme = this.isDark ? 'light' : 'dark';
    this.setTheme(newTheme);
  }
}
