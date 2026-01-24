import { Component, OnInit } from '@angular/core';
import { CommandService, CommandTemplate } from '../services/command.service';
import { AlertController, ToastController, LoadingController } from '@ionic/angular';

@Component({
  selector: 'app-commands',
  templateUrl: './commands.page.html',
  styleUrls: ['./commands.page.scss'],
  standalone: false
})
export class CommandsPage implements OnInit {
  templates: CommandTemplate[] = [];
  loading = false;

  constructor(
    private commandService: CommandService,
    private alertCtrl: AlertController,
    private toastCtrl: ToastController,
    private loadingCtrl: LoadingController
  ) { }

  ngOnInit() {
    this.loadData();
  }

  async loadData() {
    this.loading = true;
    try {
      this.templates = await this.commandService.list();
    } catch (e) {
      this.showToast('加载失败');
    } finally {
      this.loading = false;
    }
  }

  async doRefresh(event: any) {
    await this.loadData();
    event.target.complete();
  }

  async addCommand() {
    const alert = await this.alertCtrl.create({
      header: '新增命令模板',
      inputs: [
        { name: 'name', type: 'text', placeholder: '名称' },
        { name: 'command', type: 'textarea', placeholder: '命令内容' }
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '创建',
          handler: async (data) => {
            if (!data.name || !data.command) return false;
            try {
              await this.commandService.create(data);
              this.showToast('创建成功');
              this.loadData();
              return true;
            } catch (e) {
              this.showToast('创建失败');
              return false;
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async editCommand(item: CommandTemplate) {
    const alert = await this.alertCtrl.create({
      header: '编辑命令',
      inputs: [
        { name: 'name', type: 'text', value: item.name, placeholder: '名称' },
        { name: 'command', type: 'textarea', value: item.command, placeholder: '命令内容' }
      ],
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '保存',
          handler: async (data) => {
            if (!data.name || !data.command) return false;
            try {
              await this.commandService.update(item.id, data);
              this.showToast('更新成功');
              this.loadData();
              return true;
            } catch (e) {
              this.showToast('更新失败');
              return false;
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async deleteCommand(item: CommandTemplate) {
    const alert = await this.alertCtrl.create({
      header: '确认删除',
      message: `删除命令 ${item.name}?`,
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '删除',
          role: 'destructive',
          handler: async () => {
            try {
              await this.commandService.delete(item.id);
              this.showToast('已删除');
              this.loadData();
            } catch (e) {
              this.showToast('删除失败');
            }
          }
        }
      ]
    });
    await alert.present();
  }

  async showToast(msg: string) {
    const toast = await this.toastCtrl.create({ message: msg, duration: 2000 });
    toast.present();
  }
}
