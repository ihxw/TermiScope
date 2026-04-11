import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ModalController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { SSHService } from '../../../services/ssh.service';
import { SSHHostExtended } from '../../../models';
import { finalize } from 'rxjs/operators';

@Component({
  selector: 'app-hosts',
  templateUrl: './hosts.page.html',
  styleUrls: ['./hosts.page.scss'],
  standalone: false
})
export class HostsPage implements OnInit {
  hosts: SSHHostExtended[] = [];
  filteredHosts: SSHHostExtended[] = [];
  loading = false;
  searchText = '';
  showDeleted = false;
  quickFilter: 'all' | 'online' | 'offline' | 'expiring' | 'expired' | 'deleted' = 'all';

  constructor(
    private sshService: SSHService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadHosts();
  }

  async loadHosts() {
    this.loading = true;
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    const filters: any = {};
    if (this.showDeleted) {
      filters.show_deleted = 'true';
    }

    this.sshService.getHosts(filters)
      .pipe(finalize(() => {
        this.loading = false;
        loading.dismiss();
      }))
      .subscribe({
        next: (hosts) => {
          this.hosts = hosts;
          this.applyFilters();
        },
        error: async (error) => {
          const toast = await this.toastController.create({
            message: await this.translate.get('host.failLoad').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  applyFilters() {
    let result = [...this.hosts];

    // Search filter
    if (this.searchText) {
      const search = this.searchText.toLowerCase();
      result = result.filter(h => 
        h.name.toLowerCase().includes(search) ||
        h.host.toLowerCase().includes(search) ||
        h.group?.toLowerCase().includes(search)
      );
    }

    // Quick filter
    switch (this.quickFilter) {
      case 'online':
        result = result.filter(h => h.is_active);
        break;
      case 'offline':
        result = result.filter(h => !h.is_active);
        break;
      case 'deleted':
        result = result.filter(h => h.deleted_at);
        break;
    }

    this.filteredHosts = result;
  }

  handleSearch(event: any) {
    this.searchText = event.target.value;
    this.applyFilters();
  }

  toggleShowDeleted() {
    this.showDeleted = !this.showDeleted;
    this.loadHosts();
  }

  setQuickFilter(filter: 'all' | 'online' | 'offline' | 'expiring' | 'expired' | 'deleted') {
    this.quickFilter = filter;
    this.applyFilters();
  }

  async openAddHostModal() {
    const alert = await this.alertController.create({
      header: await this.translate.get('host.addHost').toPromise(),
      inputs: [
        { name: 'name', type: 'text', placeholder: await this.translate.get('host.placeholderName').toPromise() },
        { name: 'host', type: 'text', placeholder: await this.translate.get('host.placeholderHost').toPromise() },
        { name: 'port', type: 'number', value: '22', placeholder: 'Port' },
        { name: 'username', type: 'text', placeholder: await this.translate.get('host.placeholderUsername').toPromise() },
        { name: 'password', type: 'password', placeholder: await this.translate.get('host.placeholderPassword').toPromise() },
        { name: 'group', type: 'text', placeholder: await this.translate.get('host.placeholderGroup').toPromise() },
        { name: 'description', type: 'text', placeholder: await this.translate.get('host.description').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.save').toPromise(),
          handler: (data) => {
            if (data.name && data.host && data.username) {
              this.createHost(data);
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async createHost(hostData: any) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.sshService.createHost({
      ...hostData,
      port: parseInt(hostData.port) || 22,
      auth_type: hostData.password ? 'password' : 'key'
    })
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('host.successAdd').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.loadHosts();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('host.failAdd').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async editHost(host: SSHHostExtended) {
    const alert = await this.alertController.create({
      header: await this.translate.get('host.editHost').toPromise(),
      inputs: [
        { name: 'name', type: 'text', value: host.name, placeholder: await this.translate.get('host.placeholderName').toPromise() },
        { name: 'host', type: 'text', value: host.host, placeholder: await this.translate.get('host.placeholderHost').toPromise() },
        { name: 'port', type: 'number', value: host.port.toString(), placeholder: 'Port' },
        { name: 'username', type: 'text', value: host.username, placeholder: await this.translate.get('host.placeholderUsername').toPromise() },
        { name: 'password', type: 'password', placeholder: await this.translate.get('host.placeholderKeepPassword').toPromise() },
        { name: 'group', type: 'text', value: host.group || '', placeholder: await this.translate.get('host.placeholderGroup').toPromise() },
        { name: 'description', type: 'text', value: host.description || '', placeholder: await this.translate.get('host.description').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.save').toPromise(),
          handler: (data) => {
            const updateData: any = {
              name: data.name,
              host: data.host,
              port: parseInt(data.port) || 22,
              username: data.username,
              group: data.group,
              description: data.description
            };
            if (data.password) {
              updateData.password = data.password;
              updateData.auth_type = 'password';
            }
            this.updateHost(host.id, updateData);
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async updateHost(id: number, hostData: any) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.sshService.updateHost(id, hostData)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('host.successUpdate').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.loadHosts();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('host.failUpdate').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async deleteHost(host: SSHHostExtended) {
    const alert = await this.alertController.create({
      header: await this.translate.get('host.deleteHost').toPromise(),
      message: await this.translate.get('host.deleteConfirm').toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.delete').toPromise(),
          role: 'destructive',
          handler: () => {
            this.sshService.deleteHost(host.id).subscribe({
              next: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('host.hostDeleted').toPromise(),
                  duration: 2000,
                  color: 'success'
                });
                toast.present();
                this.loadHosts();
              },
              error: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('common.deleteFailed').toPromise(),
                  duration: 3000,
                  color: 'danger'
                });
                toast.present();
              }
            });
          }
        }
      ]
    });
    await alert.present();
  }

  async testConnection(host: SSHHostExtended) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('terminal.connecting').toPromise()
    });
    await loading.present();

    this.sshService.testConnection(host.id)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async (result: any) => {
          const toast = await this.toastController.create({
            message: result?.message || 'Connection successful',
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async (error) => {
          const toast = await this.toastController.create({
            message: error?.error?.error || 'Connection failed',
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async deployMonitor(host: SSHHostExtended) {
    const alert = await this.alertController.create({
      header: await this.translate.get('monitor.deployAgent').toPromise(),
      message: await this.translate.get('monitor.deployConfirm', { name: host.name }).toPromise(),
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: () => {
            this.doDeployMonitor(host);
          }
        }
      ]
    });
    await alert.present();
  }

  async doDeployMonitor(host: SSHHostExtended) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('monitor.deploying').toPromise()
    });
    await loading.present();

    this.sshService.deployMonitor(host.id)
      .pipe(finalize(() => loading.dismiss()))
      .subscribe({
        next: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.deploySuccess').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          const toast = await this.toastController.create({
            message: await this.translate.get('monitor.deployFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  getAuthTypeLabel(host: SSHHostExtended): string {
    return host.auth_type === 'password' 
      ? this.translate.instant('host.authPassword') 
      : this.translate.instant('host.authKey');
  }
}
