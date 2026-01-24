import { Component, OnInit } from '@angular/core';
import { RecordingService } from '../services/recording.service';
import { Router } from '@angular/router';
import { AlertController, ToastController } from '@ionic/angular';

@Component({
  selector: 'app-recordings',
  templateUrl: './recordings.page.html',
  styleUrls: ['./recordings.page.scss'],
  standalone: false
})
export class RecordingsPage implements OnInit {
  recordings: any[] = [];
  loading = false;

  constructor(
    private recordingService: RecordingService,
    private router: Router,
    private alertCtrl: AlertController,
    private toastCtrl: ToastController
  ) { }

  ngOnInit() {
    this.loadData();
  }

  async loadData() {
    this.loading = true;
    try {
      const res: any = await this.recordingService.list();
      this.recordings = res.data || res;
    } catch (e) {
      console.error(e);
    } finally {
      this.loading = false;
    }
  }

  doRefresh(event: any) {
    this.loadData().then(() => {
      event.target.complete();
    });
  }

  play(item: any) {
    this.router.navigate(['/recording-player'], { queryParams: { id: item.id } });
  }

  async deleteRecording(item: any) {
    const alert = await this.alertCtrl.create({
      header: '确认删除',
      message: `删除录像 ${item.id}?`,
      buttons: [
        { text: '取消', role: 'cancel' },
        {
          text: '删除',
          role: 'destructive',
          handler: async () => {
            try {
              await this.recordingService.delete(item.id);
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
