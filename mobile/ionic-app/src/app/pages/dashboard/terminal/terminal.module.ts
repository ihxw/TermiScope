import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IonicModule } from '@ionic/angular';
import { TranslateModule } from '@ngx-translate/core';

import { TerminalPageRoutingModule } from './terminal-routing.module';
import { TerminalPage } from './terminal.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    TranslateModule,
    TerminalPageRoutingModule
  ],
  declarations: [TerminalPage]
})
export class TerminalPageModule {}
