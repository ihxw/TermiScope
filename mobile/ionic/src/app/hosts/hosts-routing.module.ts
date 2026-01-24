import { NgModule } from '@angular/core';
import { Routes, RouterModule } from '@angular/router';

import { HostsPage } from './hosts.page';

const routes: Routes = [
  {
    path: '',
    component: HostsPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class HostsPageRoutingModule {}
