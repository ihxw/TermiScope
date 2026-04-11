import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';
import { TranslateModule } from '@ngx-translate/core';

import { SystemPageRoutingModule } from './system-routing.module';
import { SystemPage } from './system.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    TranslateModule,
    SystemPageRoutingModule
  ],
  declarations: [SystemPage]
})
export class SystemPageModule {}
