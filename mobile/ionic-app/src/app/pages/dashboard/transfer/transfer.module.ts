import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';
import { TranslateModule } from '@ngx-translate/core';

import { TransferPageRoutingModule } from './transfer-routing.module';
import { TransferPage } from './transfer.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    TranslateModule,
    TransferPageRoutingModule
  ],
  declarations: [TransferPage]
})
export class TransferPageModule {}
