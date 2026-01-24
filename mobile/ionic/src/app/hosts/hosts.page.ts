import { Component, OnInit } from '@angular/core';
import { HostService, Host } from '../services/host.service';
import { Observable } from 'rxjs';
import { AlertController, ToastController } from '@ionic/angular';
import { Router } from '@angular/router';

@Component({
  selector: 'app-hosts',
  templateUrl: './hosts.page.html',
  styleUrls: ['./hosts.page.scss'],
  standalone: false
})
export class HostsPage implements OnInit {
  hosts$: Observable<Host[]>;
  loading = false;

  constructor(
    private hostService: HostService,
    private alertController: AlertController,
    private toastController: ToastController,
    private router: Router
  ) {
    this.hosts$ = this.hostService.hosts$;
  }

  ngOnInit() {
    this.loadData();
  }

  async loadData() {
    this.loading = true;
    try {
      await this.hostService.fetchHosts();
    } finally {
      this.loading = false;
    }
  }

  doRefresh(event: any) {
    this.loadData().then(() => {
      event.target.complete();
    });
  }

  async openAddModal() {
    // For MVP, using Alert input. For full features, use a Modal with a form.
    const alert = await this.alertController.create({
      header: 'Add Host',
      inputs: [
        { name: 'name', type: 'text', placeholder: 'Name' },
        { name: 'host', type: 'text', placeholder: 'Host/IP' },
        { name: 'port', type: 'number', placeholder: 'Port', value: 22 },
        { name: 'username', type: 'text', placeholder: 'Username' },
        { name: 'password', type: 'password', placeholder: 'Password (Optional if Key)' },
      ],
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Add',
          handler: (data) => {
            if (!data.name || !data.host || !data.username) {
              this.showToast('Please fill required fields', 'warning');
              return false;
            }
            this.addHost(data);
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async addHost(data: any) {
    try {
      // Default to password auth if password provided, otherwise needs more complex UI
      const payload = {
        ...data,
        port: parseInt(data.port),
        auth_type: data.password ? 'password' : 'key', // Simplified logic
        host_type: 'control_monitor' // Default
      };
      await this.hostService.addHost(payload);
      this.showToast('Host added successfully');
    } catch (e) {
      // Error handled in service or interceptor usually, but...
    }
  }

  async openEditModal(host: Host) {
    // Simplified Edit
    const alert = await this.alertController.create({
      header: 'Edit Host',
      inputs: [
        { name: 'name', type: 'text', value: host.name, placeholder: 'Name' },
        { name: 'host', type: 'text', value: host.host, placeholder: 'Host/IP' },
      ],
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Update',
          handler: (data) => {
            this.hostService.updateHost(host.id, { ...host, ...data });
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async deleteHost(host: Host) {
    const alert = await this.alertController.create({
      header: 'Confirm Delete',
      message: `Delete host ${host.name}?`,
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Delete',
          role: 'destructive',
          handler: async () => {
            await this.hostService.deleteHost(host.id);
            this.showToast('Host deleted');
          }
        }
      ]
    });
    await alert.present();
  }

  async showToast(msg: string, color: string = 'success') {
    const toast = await this.toastController.create({
      message: msg,
      duration: 2000,
      color: color
    });
    toast.present();
  }

  connect(host: Host) {
    this.router.navigate(['/terminal'], { queryParams: { id: host.id, name: host.name } });
  }

  openSftp(host: Host) {
    this.router.navigate(['/sftp-browser'], { queryParams: { id: host.id } });
  }
}
