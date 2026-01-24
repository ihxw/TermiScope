import { Component, OnInit } from '@angular/core';
import { ApiService } from '../services/api.service';

@Component({
  selector: 'app-history',
  templateUrl: './history.page.html',
  styleUrls: ['./history.page.scss'],
  standalone: false
})
export class HistoryPage implements OnInit {
  logs: any[] = [];
  loading = false;

  constructor(private api: ApiService) { }

  ngOnInit() {
    this.loadData();
  }

  async loadData() {
    this.loading = true;
    try {
      const res: any = await this.api.get('/connection-logs');
      this.logs = res.data || res;
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
}
