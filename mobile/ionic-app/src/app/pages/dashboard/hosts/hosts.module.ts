import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';
import { TranslateModule } from '@ngx-translate/core';

import { HostsPageRoutingModule } from './hosts-routing.module';
import { HostsPage } from './hosts.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    TranslateModule,
    HostsPageRoutingModule
  ],
  declarations: [HostsPage]
})
export class HostsPageModule {}
