import { Component, OnInit } from '@angular/core';
import { NetworkService, NetworkTask } from '../services/network.service';
import { AlertController, ToastController, LoadingController } from '@ionic/angular';

@Component({
  selector: 'app-network-monitor',
  templateUrl: './network-monitor.page.html',
  styleUrls: ['./network-monitor.page.scss'],
  standalone: false
})
export class NetworkMonitorPage implements OnInit {
  tasks: NetworkTask[] = [];
  loading = false;

  constructor(
    private networkService: NetworkService,
    private alertCtrl: AlertController,
    private toastCtrl: ToastController,
    private loadingCtrl: LoadingController
  ) { }

  ngOnInit() {
    this.loadTasks();
  }

  async loadTasks() {
    this.loading = true;
    try {
      this.tasks = await this.networkService.listTasks();
    } catch (e) {
      this.showToast('加载失败');
    } finally {
      this.loading = false;
    }
  }

  async doRefresh(event: any) {
    await this.loadTasks();
    event.target.complete();
  }

  async addTask() {
    const alert = await this.alertCtrl.create({
      header: '新增监控任务',
      inputs: [
        { name: 'name', type: 'text', placeholder: '任务名称' },
        { name: 'target', type: 'text', placeholder: '目标 (IP/域名/URL)' },
        { name: 'type', type: 'text', placeholder: '类型 (ping/tcp/http)', value: 'ping' },
        { name: 'interval', type: 'number', placeholder: '间隔 (秒)', value: 60 },
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '创建',
          handler: (data) => {
            if (!data.name || !data.target) {
              this.showToast('名称和目标必填');
              return false;
            }
            this.createTaskConfirm({
              ...data,
              interval: parseInt(data.interval),
              timeout: 5,
              is_active: true
            });
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async createTaskConfirm(task: any) {
    const loading = await this.loadingCtrl.create({ message: '创建中...' });
    await loading.present();
    try {
      await this.networkService.createTask(task);
      this.showToast('创建成功');
      this.loadTasks();
    } catch (e) {
      this.showToast('创建失败');
    } finally {
      loading.dismiss();
    }
  }

  async deleteTask(task: NetworkTask) {
    const alert = await this.alertCtrl.create({
      header: '确认删除',
      message: `删除任务 ${task.name}?`,
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '删除',
          role: 'destructive',
          handler: async () => {
            await this.networkService.deleteTask(task.id);
            this.loadTasks();
          }
        }
      ]
    });
    await alert.present();
  }

  async showStats(task: NetworkTask) {
    // Placeholder for Stats page navigation
    this.showToast('统计图表功能开发中: ' + task.name);
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({
      message: msg,
      duration: 2000
    });
    toast.present();
  }
}
