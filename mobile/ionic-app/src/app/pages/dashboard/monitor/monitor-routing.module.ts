import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { MonitorPage } from './monitor.page';

const routes: Routes = [
  {
    path: '',
    component: MonitorPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})
export class MonitorPageRoutingModule {}
