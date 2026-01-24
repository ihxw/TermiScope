import { NgModule } from '@angular/core';
import { Routes, RouterModule } from '@angular/router';

import { CommandsPage } from './commands.page';

const routes: Routes = [
  {
    path: '',
    component: CommandsPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class CommandsPageRoutingModule {}
