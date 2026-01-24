import { Component, OnInit } from '@angular/core';
import { ApiService } from '../services/api.service';
import { ToastController } from '@ionic/angular';

@Component({
  selector: 'app-settings',
  templateUrl: './settings.page.html',
  styleUrls: ['./settings.page.scss'],
  standalone: false
})
export class SettingsPage implements OnInit {
  serverUrl = '';

  constructor(
    private api: ApiService,
    private toastController: ToastController
  ) { }

  ngOnInit() {
    this.serverUrl = localStorage.getItem('server_url') || '';
  }

  async saveSettings() {
    if (!this.serverUrl) return;
    this.api.updateBaseUrl(this.serverUrl);
    const toast = await this.toastController.create({
      message: '设置已保存',
      duration: 2000,
      color: 'success'
    });
    toast.present();
  }
}
