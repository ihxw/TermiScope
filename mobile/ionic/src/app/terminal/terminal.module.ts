import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { TerminalPageRoutingModule } from './terminal-routing.module';

import { TerminalPage } from './terminal.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    TerminalPageRoutingModule
  ],
  declarations: [TerminalPage]
})
export class TerminalPageModule {}
