import { NgModule } from '@angular/core';
import { Routes, RouterModule } from '@angular/router';

import { NetworkMonitorPage } from './network-monitor.page';

const routes: Routes = [
  {
    path: '',
    component: NetworkMonitorPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class NetworkMonitorPageRoutingModule {}
