import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { CommandService } from '../../../services/data.service';
import { Command } from '../../../models';

@Component({
  selector: 'app-commands',
  templateUrl: './commands.page.html',
  styleUrls: ['./commands.page.scss'],
  standalone: false
})
export class CommandsPage implements OnInit {
  commands: Command[] = [];
  loading = false;

  constructor(
    private commandService: CommandService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadCommands();
  }

  async loadCommands() {
    this.loading = true;
    // Web 端: GET /command-templates 无分页，返回直接数组
    this.commandService.getCommands()
      .subscribe({
        next: (result: any) => {
          this.commands = result || [];
          this.loading = false;
        },
        error: async () => {
          this.loading = false;
          const toast = await this.toastController.create({
            message: await this.translate.get('command.loadFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async addCommand() {
    const alert = await this.alertController.create({
      header: await this.translate.get('command.addCommand').toPromise(),
      inputs: [
        { name: 'name', type: 'text', placeholder: await this.translate.get('command.name').toPromise() },
        { name: 'command', type: 'text', placeholder: await this.translate.get('command.command').toPromise() },
        { name: 'description', type: 'text', placeholder: await this.translate.get('command.description').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.save').toPromise(),
          handler: (data) => {
            if (data.name && data.command) {
              this.createCommand(data);
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async createCommand(data: any) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.commandService.createCommand(data)
      .subscribe({
        next: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('command.templateCreated').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.loadCommands();
        },
        error: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('command.saveFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  // Web 端支持编辑命令模板
  async editCommand(command: Command) {
    const alert = await this.alertController.create({
      header: await this.translate.get('command.editTemplate').toPromise(),
      inputs: [
        { name: 'name', type: 'text', value: command.name, placeholder: await this.translate.get('command.name').toPromise() },
        { name: 'command', type: 'text', value: command.command, placeholder: await this.translate.get('command.command').toPromise() },
        { name: 'description', type: 'text', value: command.description, placeholder: await this.translate.get('command.description').toPromise() }
      ],
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.save').toPromise(),
          handler: (data) => {
            if (data.name && data.command) {
              this.doUpdateCommand(command.id, data);
            }
            return true;
          }
        }
      ]
    });
    await alert.present();
  }

  async doUpdateCommand(id: number, data: any) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.commandService.updateCommand(id, data)
      .subscribe({
        next: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('command.templateUpdated').toPromise(),
            duration: 2000,
            color: 'success'
          });
          toast.present();
          this.loadCommands();
        },
        error: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: await this.translate.get('command.saveFailed').toPromise(),
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  async deleteCommand(command: Command) {
    const alert = await this.alertController.create({
      header: await this.translate.get('command.deleteCommand').toPromise(),
      message: command.name,
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.delete').toPromise(),
          role: 'destructive',
          handler: () => {
            this.commandService.deleteCommand(command.id).subscribe({
              next: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('command.templateDeleted').toPromise(),
                  duration: 2000,
                  color: 'success'
                });
                toast.present();
                this.loadCommands();
              },
              error: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('command.deleteFailed').toPromise(),
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

  // Note: Web 端没有"快速执行"功能，命令模板仅在终端中手动使用
  // 已移除 executeCommand 和 doExecuteCommand 方法
}
