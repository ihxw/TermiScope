import { Component, OnInit } from '@angular/core';
import { AlertController, LoadingController, ToastController } from '@ionic/angular';
import { TranslateService } from '@ngx-translate/core';
import { RecordingService } from '../../../services/data.service';
import { Recording } from '../../../models';

@Component({
  selector: 'app-recordings',
  templateUrl: './recordings.page.html',
  styleUrls: ['./recordings.page.scss'],
  standalone: false
})
export class RecordingsPage implements OnInit {
  recordings: Recording[] = [];
  loading = false;
  page = 1;
  pageSize = 20;

  constructor(
    private recordingService: RecordingService,
    private alertController: AlertController,
    private loadingController: LoadingController,
    private toastController: ToastController,
    private translate: TranslateService
  ) {}

  ngOnInit() {
    this.loadRecordings();
  }

  async loadRecordings() {
    this.loading = true;
    this.recordingService.getRecordings(this.page, this.pageSize)
      .subscribe({
        next: (result: any) => {
          this.recordings = result.items || [];
          this.loading = false;
        },
        error: async () => {
          this.loading = false;
          const toast = await this.toastController.create({
            message: 'Failed to load recordings',
            duration: 3000,
            color: 'danger'
          });
          toast.present();
        }
      });
  }

  formatSize(size: number): string {
    if (!size) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    let i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return `${size.toFixed(1)} ${units[i]}`;
  }

  formatDuration(seconds: number): string {
    if (!seconds) return '-';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  formatDate(dateStr: string): string {
    if (!dateStr) return '-';
    return new Date(dateStr).toLocaleString();
  }

  playRecording(recording: Recording) {
    const url = this.recordingService.getRecordingStreamUrl(recording.session_id);
    window.open(url, '_blank');
  }

  async deleteRecording(recording: Recording) {
    const alert = await this.alertController.create({
      header: await this.translate.get('recording.delete').toPromise(),
      message: recording.session_id,
      buttons: [
        { text: await this.translate.get('common.cancel').toPromise(), role: 'cancel' },
        {
          text: await this.translate.get('common.delete').toPromise(),
          role: 'destructive',
          handler: () => {
            this.recordingService.deleteRecording(recording.id).subscribe({
              next: async () => {
                const toast = await this.toastController.create({
                  message: await this.translate.get('recording.recordingDeleted').toPromise(),
                  duration: 2000,
                  color: 'success'
                });
                toast.present();
                this.loadRecordings();
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
}
