import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { Storage } from '@ionic/storage-angular';
import { TranslateService } from '@ngx-translate/core';

type Locale = 'zh-CN' | 'en-US';

@Injectable({
  providedIn: 'root'
})
export class LocaleStore {
  private localeSubject = new BehaviorSubject<Locale>('zh-CN');
  locale$ = this.localeSubject.asObservable();
  private initialized = false;

  constructor(
    private storage: Storage,
    private translate: TranslateService
  ) {
    this.init();
  }

  private async init() {
    await this.storage.create();
    
    // Set default language
    this.translate.setDefaultLang('zh-CN');
    
    const savedLocale = await this.storage.get('locale') as Locale;
    if (savedLocale) {
      this.setLocale(savedLocale, false);
    } else {
      // Check browser language
      const browserLang = navigator.language;
      const locale: Locale = browserLang.startsWith('zh') ? 'zh-CN' : 'en-US';
      this.setLocale(locale, false);
    }
    this.initialized = true;
  }

  get locale(): Locale {
    return this.localeSubject.value;
  }

  get isInitialized(): boolean {
    return this.initialized;
  }

  get nextLanguage(): string {
    return this.locale === 'zh-CN' ? 'English' : '中文';
  }

  setLocale(locale: Locale, save: boolean = true): void {
    this.localeSubject.next(locale);
    this.translate.use(locale);
    
    if (save) {
      this.storage.set('locale', locale);
    }
  }

  toggleLocale(): void {
    const newLocale: Locale = this.locale === 'zh-CN' ? 'en-US' : 'zh-CN';
    this.setLocale(newLocale);
  }

  // Get translation instantly
  instant(key: string, params?: any): string {
    return this.translate.instant(key, params);
  }
}
