import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { RecordingPlayerPageRoutingModule } from './recording-player-routing.module';

import { RecordingPlayerPage } from './recording-player.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    RecordingPlayerPageRoutingModule
  ],
  declarations: [RecordingPlayerPage]
})
export class RecordingPlayerPageModule {}
