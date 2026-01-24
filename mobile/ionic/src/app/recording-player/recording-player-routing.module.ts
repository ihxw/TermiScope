import { NgModule } from '@angular/core';
import { Routes, RouterModule } from '@angular/router';

import { RecordingPlayerPage } from './recording-player.page';

const routes: Routes = [
  {
    path: '',
    component: RecordingPlayerPage
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
})
export class RecordingPlayerPageRoutingModule {}
