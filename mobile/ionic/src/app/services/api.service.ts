import { Injectable } from '@angular/core';
import axios, { AxiosInstance, AxiosRequestConfig, AxiosError } from 'axios';
import { ToastController } from '@ionic/angular';
import { Router } from '@angular/router';

@Injectable({
    providedIn: 'root'
})
export class ApiService {
    private http: AxiosInstance;

    constructor(
        private toastController: ToastController,
        private router: Router
    ) {
        const savedUrl = localStorage.getItem('server_url') || '';
        this.http = axios.create({
            baseURL: savedUrl ? `${savedUrl}/api` : '/api',
            timeout: 10000
        });

        this.setupInterceptors();
    }

    public updateBaseUrl(newUrl: string) {
        if (newUrl) {
            this.http.defaults.baseURL = `${newUrl}/api`;
            localStorage.setItem('server_url', newUrl);
        }
    }

    private setupInterceptors() {
        // Request Interceptor
        this.http.interceptors.request.use(
            (config: any) => {
                const token = localStorage.getItem('token');
                if (token && config.headers) {
                    config.headers.Authorization = `Bearer ${token}`;
                }
                return config;
            },
            (error: any) => Promise.reject(error)
        );

        // Response Interceptor
        this.http.interceptors.response.use(
            (response: any) => {
                if (response.data && response.data.success) {
                    // Web app unwraps: return response.data.data. 
                    return response.data.data;
                }
                return response.data;
            },
            async (error: AxiosError) => {
                const originalRequest = error.config as AxiosRequestConfig & { _retry?: boolean };
                let errorMessage = 'Request failed';

                if (error.response?.data && (error.response.data as any).error) {
                    errorMessage = (error.response.data as any).error;
                } else if (error.message) {
                    errorMessage = error.message;
                }

                // Handle 401
                if (error.response?.status === 401 && !originalRequest._retry) {
                    if (originalRequest.url?.includes('/auth/login')) {
                        return Promise.reject(error);
                    }

                    // Simplified refresh logic for now: Redirect to login
                    await this.showToast('Session expired, please login again');
                    localStorage.removeItem('token');
                    localStorage.removeItem('refresh_token');
                    this.router.navigate(['/login']);
                    return Promise.reject(error);
                }

                await this.showToast(errorMessage);
                return Promise.reject(error);
            }
        );
    }

    private async showToast(message: string) {
        const toast = await this.toastController.create({
            message: message,
            duration: 3000,
            position: 'bottom',
            color: 'danger'
        });
        toast.present();
    }

    get<T>(url: string, params?: any, config?: AxiosRequestConfig): Promise<T> {
        return this.http.get<T>(url, { params, ...config }) as any;
    }

    post<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
        return this.http.post<T>(url, data, config) as any;
    }

    put<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
        return this.http.put<T>(url, data, config) as any;
    }

    delete<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
        return this.http.delete<T>(url, config) as any;
    }
}
