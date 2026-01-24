import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { NetworkDetailPageRoutingModule } from './network-detail-routing.module';

import { NetworkDetailPage } from './network-detail.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    NetworkDetailPageRoutingModule
  ],
  declarations: [NetworkDetailPage]
})
export class NetworkDetailPageModule {}
