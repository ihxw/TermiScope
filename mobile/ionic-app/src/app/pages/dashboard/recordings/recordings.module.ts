import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';
import { TranslateModule } from '@ngx-translate/core';

import { RecordingsPageRoutingModule } from './recordings-routing.module';
import { RecordingsPage } from './recordings.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    TranslateModule,
    RecordingsPageRoutingModule
  ],
  declarations: [RecordingsPage]
})
export class RecordingsPageModule {}
