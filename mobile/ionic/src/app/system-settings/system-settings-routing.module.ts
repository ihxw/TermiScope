import { NgModule } from '@angular/core';
import { Routes, RouterModule } from '@angular/router';

import { SystemSettingsPage } from './system-settings.page';

const routes: Routes = [
  {
    path: '',
    component: SystemSettingsPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class SystemSettingsPageRoutingModule {}
