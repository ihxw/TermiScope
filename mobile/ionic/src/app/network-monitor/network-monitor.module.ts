import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { NetworkMonitorPageRoutingModule } from './network-monitor-routing.module';

import { NetworkMonitorPage } from './network-monitor.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    NetworkMonitorPageRoutingModule
  ],
  declarations: [NetworkMonitorPage]
})
export class NetworkMonitorPageModule {}
