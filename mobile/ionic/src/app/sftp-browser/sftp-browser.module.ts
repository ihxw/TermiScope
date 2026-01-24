import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { IonicModule } from '@ionic/angular';

import { SftpBrowserPageRoutingModule } from './sftp-browser-routing.module';

import { SftpBrowserPage } from './sftp-browser.page';

@NgModule({
  imports: [
    CommonModule,
    FormsModule,
    IonicModule,
    SftpBrowserPageRoutingModule
  ],
  declarations: [SftpBrowserPage]
})
export class SftpBrowserPageModule {}
