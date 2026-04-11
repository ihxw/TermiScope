import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { TerminalPage } from './terminal.page';

const routes: Routes = [
  {
    path: '',
    component: TerminalPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})
export class TerminalPageRoutingModule {}
