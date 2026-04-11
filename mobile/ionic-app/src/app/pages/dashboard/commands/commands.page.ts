import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { CommandService } from '../../../services/data.service';
import { SSHService } from '../../../services/ssh.service';
import { Command, SSHHostExtended } from '../../../models';

@Component({
  selector: 'app-commands',
  templateUrl: './commands.page.html',
  styleUrls: ['./commands.page.scss'],
  standalone: false
})
export class CommandsPage implements OnInit {
  commands: Command[] = [];
  hosts: SSHHostExtended[] = [];
  loading = false;
  page = 1;
  pageSize = 20;

  constructor(
    private commandService: CommandService,
    private sshService: SSHService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadCommands();
    this.loadHosts();
  }

  async loadCommands() {
    this.loading = true;
    this.commandService.getCommands(this.page, this.pageSize)
      .subscribe({
        next: (result: any) => {
          this.commands = result.items || [];
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

  async loadHosts() {
    this.sshService.getHosts().subscribe({
      next: (hosts) => {
        this.hosts = hosts.filter((h: SSHHostExtended) => h.host_type !== 'monitor');
      },
      error: () => {}
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

  async executeCommand(command: Command) {
    // Show host selection
    const buttons = this.hosts.map(host => ({
      text: host.name,
      handler: () => {
        this.doExecuteCommand(host.id, command.id);
        return true;
      }
    }));
    
    (buttons as any[]).push({
      text: await this.translate.get('common.cancel').toPromise(),
      role: 'cancel'
    });

    const alert = await this.alertController.create({
      header: await this.translate.get('terminal.selectHost').toPromise(),
      buttons: buttons
    });
    await alert.present();
  }

  async doExecuteCommand(hostId: number, commandId: number) {
    const loading = await this.loadingController.create({
      message: await this.translate.get('common.loading').toPromise()
    });
    await loading.present();

    this.commandService.executeCommand(hostId, commandId)
      .subscribe({
        next: async (result: any) => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: result?.message || 'Command executed',
            duration: 2000,
            color: 'success'
          });
          toast.present();
        },
        error: async () => {
          loading.dismiss();
          const toast = await this.toastController.create({
            message: 'Failed to execute command',
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }
}
