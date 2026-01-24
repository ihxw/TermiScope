import { NgModule } from '@angular/core';
import { Routes, RouterModule } from '@angular/router';

import { SftpBrowserPage } from './sftp-browser.page';

const routes: Routes = [
  {
    path: '',
    component: SftpBrowserPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class SftpBrowserPageRoutingModule {}
