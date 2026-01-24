import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { SystemSettingsPageRoutingModule } from './system-settings-routing.module';

import { SystemSettingsPage } from './system-settings.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    SystemSettingsPageRoutingModule
  ],
  declarations: [SystemSettingsPage]
})
export class SystemSettingsPageModule {}
