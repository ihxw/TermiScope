import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { CommandsPageRoutingModule } from './commands-routing.module';

import { CommandsPage } from './commands.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    CommandsPageRoutingModule
  ],
  declarations: [CommandsPage]
})
export class CommandsPageModule {}
