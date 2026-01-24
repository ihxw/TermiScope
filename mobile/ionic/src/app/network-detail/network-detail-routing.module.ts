import { NgModule } from '@angular/core';
import { Routes, RouterModule } from '@angular/router';

import { NetworkDetailPage } from './network-detail.page';

const routes: Routes = [
  {
    path: '',
    component: NetworkDetailPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class NetworkDetailPageRoutingModule {}
