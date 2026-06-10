import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { SSHService } from '../../../services/ssh.service';
import { SFTPService } from '../../../services/data.service';
import { SSHHostExtended, SFTPFile } from '../../../models';

@Component({
  selector: 'app-transfer',
  templateUrl: './transfer.page.html',
  styleUrls: ['./transfer.page.scss'],
  standalone: false
})
export class TransferPage implements OnInit {
  hosts: SSHHostExtended[] = [];
  selectedHost: SSHHostExtended | null = null;
  currentPath = '/';
  files: SFTPFile[] = [];
  loading = false;
  pathHistory: string[] = [];

  constructor(
    private sshService: SSHService,
    private sftpService: SFTPService,
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
    this.sshService.getHosts().subscribe({
      next: (hosts) => {
        this.hosts = hosts;
        this.loading = false;
      },
      error: async () => {
        this.loading = false;
        const toast = await this.toastController.create({
          message: await this.translate.get('host.failLoad').toPromise(),
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }

  selectHost(host: SSHHostExtended) {
    this.selectedHost = host;
    this.currentPath = '/';
    this.pathHistory = [];
    this.loadFiles();
  }

  async loadFiles() {
    if (!this.selectedHost) return;
    
    this.loading = true;
    this.sftpService.listFiles(this.selectedHost.id, this.currentPath).subscribe({
      next: (files) => {
        this.files = files.sort((a, b) => {
          // Directories first
          if (a.is_dir && !b.is_dir) return -1;
          if (!a.is_dir && b.is_dir) return 1;
          return a.name.localeCompare(b.name);
        });
        this.loading = false;
      },
      error: async () => {
        this.loading = false;
        const toast = await this.toastController.create({
          message: 'Failed to load files',
          duration: 3000,
          color: 'danger'
        });
        toast.present();
      }
    });
  }

  navigateTo(file: SFTPFile) {
    if (file.is_dir) {
      this.pathHistory.push(this.currentPath);
      this.currentPath = file.path;
      this.loadFiles();
    }
  }

  navigateUp() {
    if (this.pathHistory.length > 0) {
      this.currentPath = this.pathHistory.pop() || '/';
      this.loadFiles();
    } else {
      this.currentPath = '/';
      this.loadFiles();
    }
  }

  get isRoot(): boolean {
    return this.currentPath === '/';
  }

  async createFolder() {
    const alert = await this.alertController.create({
      header: await this.translate.get('sftp.newFolder').toPromise(),
      inputs: [
        { name: 'name', type: 'text', placeholder: await this.translate.get('sftp.folderName').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.confirm').toPromise(),
          handler: (data) => {
            if (data.name && this.selectedHost) {
              const path = this.currentPath === '/' ? `/${data.name}` : `${this.currentPath}/${data.name}`;
              this.sftpService.createDirectory(this.selectedHost.id, path).subscribe({
                next: async () => {
                  const toast = await this.toastController.create({
                    message: await this.translate.get('sftp.created', { type: 'folder' }).toPromise(),
                    duration: 2000,
                    color: 'success'
                  });
                  toast.present();
                  this.loadFiles();
                },
                error: async () => {
                  const toast = await this.toastController.create({
                    message: await this.translate.get('sftp.failedToCreate', { type: 'folder' }).toPromise(),
                    duration: 3000,
                    color: 'danger'
                  });
                  toast.present();
                }
              });
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async deleteFile(file: SFTPFile) {
    const alert = await this.alertController.create({
      header: await this.translate.get('common.confirmDelete').toPromise(),
      message: file.name,
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.delete').toPromise(),
          role: 'destructive',
          handler: () => {
            if (this.selectedHost) {
              this.sftpService.deleteFile(this.selectedHost.id, file.path).subscribe({
                next: async () => {
                  const toast = await this.toastController.create({
                    message: await this.translate.get('sftp.deleted').toPromise(),
                    duration: 2000,
                    color: 'success'
                  });
                  toast.present();
                  this.loadFiles();
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
        }
      ]
    });
    await alert.present();
  }

  formatSize(size: number): string {
    if (size === 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return `${size.toFixed(1)} ${units[i]}`;
  }

  goBack() {
    this.selectedHost = null;
    this.files = [];
    this.currentPath = '/';
  }
}
