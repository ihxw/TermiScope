import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { RecordingsPageRoutingModule } from './recordings-routing.module';

import { RecordingsPage } from './recordings.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    RecordingsPageRoutingModule
  ],
  declarations: [RecordingsPage]
})
export class RecordingsPageModule {}
