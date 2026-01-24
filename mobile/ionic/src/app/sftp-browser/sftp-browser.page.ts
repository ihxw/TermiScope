import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { SftpService, FileEntry } from '../services/sftp.service';
import { AlertController, ActionSheetController, ToastController, LoadingController } from '@ionic/angular';

@Component({
  selector: 'app-sftp-browser',
  templateUrl: './sftp-browser.page.html',
  styleUrls: ['./sftp-browser.page.scss'],
  standalone: false
})
export class SftpBrowserPage implements OnInit {
  hostId: string | null = null;
  currentPath: string = '.';
  files: FileEntry[] = [];
  loading = false;
  history: string[] = [];

  constructor(
    private route: ActivatedRoute,
    private sftp: SftpService,
    private alertCtrl: AlertController,
    private actionSheetCtrl: ActionSheetController,
    private toastCtrl: ToastController,
    private loadingCtrl: LoadingController
  ) { }

  ngOnInit() {
    this.hostId = this.route.snapshot.queryParamMap.get('id');
    if (this.hostId) {
      this.loadFiles('.');
    }
  }

  async loadFiles(path: string) {
    this.loading = true;
    try {
      const res = await this.sftp.listFiles(this.hostId!, path);
      this.files = res.sort((a, b) => {
        if (a.is_dir && !b.is_dir) return -1;
        if (!a.is_dir && b.is_dir) return 1;
        return a.name.localeCompare(b.name);
      });
      this.currentPath = path;
    } catch (e: any) {
      this.showToast('加载失败: ' + (e.message || e));
    } finally {
      this.loading = false;
    }
  }

  async doRefresh(event: any) {
    await this.loadFiles(this.currentPath);
    event.target.complete();
  }

  formatSize(bytes: number) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  }

  formatDate(modTime: string) {
    return new Date(modTime).toLocaleString();
  }

  async itemClicked(file: FileEntry) {
    if (file.is_dir) {
      let newPath = file.path;
      if (!newPath) {
        if (this.currentPath === '.') newPath = file.name;
        else newPath = this.currentPath + '/' + file.name;
      }
      this.history.push(this.currentPath);
      this.loadFiles(newPath);
    } else {
      this.showFileActionSheet(file);
    }
  }

  goBack() {
    if (this.history.length > 0) {
      const prev = this.history.pop();
      this.loadFiles(prev!);
    } else if (this.currentPath !== '.') {
      this.loadFiles('.');
    }
  }

  async showFileActionSheet(file: FileEntry) {
    const actionSheet = await this.actionSheetCtrl.create({
      header: file.name,
      buttons: [
        {
          text: '下载文件',
          icon: 'download',
          handler: () => {
            this.downloadFile(file);
          }
        },
        {
          text: '重命名',
          icon: 'create',
          handler: () => {
            this.renameFile(file);
          }
        },
        {
          text: '删除',
          role: 'destructive',
          icon: 'trash',
          handler: () => {
            this.deleteFile(file);
          }
        },
        {
          text: '取消',
          role: 'cancel',
          icon: 'close'
        }
      ]
    });
    await actionSheet.present();
  }

  async downloadFile(file: FileEntry) {
    const loading = await this.loadingCtrl.create({ message: '下载中...' });
    await loading.present();
    try {
      const blob: any = await this.sftp.downloadFile(this.hostId!, file.path || (this.currentPath + '/' + file.name));
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = file.name;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
      this.showToast('下载已开始');
    } catch (e) {
      this.showToast('下载失败');
      console.error(e);
    } finally {
      loading.dismiss();
    }
  }

  async deleteFile(file: FileEntry) {
    const alert = await this.alertCtrl.create({
      header: '确认删除',
      message: `确定要删除 ${file.name} 吗？`,
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '删除',
          role: 'destructive',
          handler: async () => {
            await this.sftp.deleteFile(this.hostId!, file.path || file.name);
            this.showToast('已删除');
            this.loadFiles(this.currentPath);
          }
        }
      ]
    });
    await alert.present();
  }

  async renameFile(file: FileEntry) {
    const alert = await this.alertCtrl.create({
      header: '重命名',
      inputs: [{ name: 'newName', value: file.name, placeholder: '新文件名' }],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '确定',
          handler: async (data) => {
            if (data.newName && data.newName !== file.name) {
              const oldPath = file.path || this.currentPath + '/' + file.name;
              let parent = '.';
              if (typeof file.path === 'string' && file.path.includes('/')) {
                parent = file.path.substring(0, file.path.lastIndexOf('/'));
              } else if (this.currentPath !== '.') {
                parent = this.currentPath;
              }
              const newPath = parent === '.' ? data.newName : parent + '/' + data.newName;
              await this.sftp.rename(this.hostId!, oldPath, newPath);
              this.showToast('重命名成功');
              this.loadFiles(this.currentPath);
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async uploadFile(event: any) {
    const file = event.target.files[0];
    if (!file) return;

    const loading = await this.loadingCtrl.create({ message: '上传中...' });
    await loading.present();
    try {
      await this.sftp.upload(this.hostId!, this.currentPath, file);
      this.showToast('上传成功');
      this.loadFiles(this.currentPath);
    } catch (e) {
      this.showToast('上传失败');
      console.error(e);
    } finally {
      loading.dismiss();
      // Reset input
      event.target.value = '';
    }
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({
      message: msg,
      duration: 2000
    });
    toast.present();
  }
}
