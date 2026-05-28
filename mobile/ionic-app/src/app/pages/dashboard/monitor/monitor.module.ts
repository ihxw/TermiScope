import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';
import { TranslateModule } from '@ngx-translate/core';

import { MonitorPageRoutingModule } from './monitor-routing.module';
import { MonitorPage } from './monitor.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    TranslateModule,
    MonitorPageRoutingModule
  ],
  declarations: [MonitorPage]
})
export class MonitorPageModule {}
