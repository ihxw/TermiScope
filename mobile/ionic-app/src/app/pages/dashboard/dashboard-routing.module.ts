import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { DashboardPage } from './dashboard.page';

const routes: Routes = [
  {
    path: '',
    component: DashboardPage,
    children: [
      {
        path: 'terminal',
        loadChildren: () => import('./terminal/terminal.module').then(m => m.TerminalPageModule)
      },
      {
        path: 'monitor',
        loadChildren: () => import('./monitor/monitor.module').then(m => m.MonitorPageModule)
      },
      {
        path: 'hosts',
        loadChildren: () => import('./hosts/hosts.module').then(m => m.HostsPageModule)
      },
      {
        path: 'history',
        loadChildren: () => import('./history/history.module').then(m => m.HistoryPageModule)
      },
      {
        path: 'commands',
        loadChildren: () => import('./commands/commands.module').then(m => m.CommandsPageModule)
      },
      {
        path: 'recordings',
        loadChildren: () => import('./recordings/recordings.module').then(m => m.RecordingsPageModule)
      },
      {
        path: 'transfer',
        loadChildren: () => import('./transfer/transfer.module').then(m => m.TransferPageModule)
      },
      {
        path: 'users',
        loadChildren: () => import('./users/users.module').then(m => m.UsersPageModule),
        data: { requiresAdmin: true }
      },
      {
        path: 'profile',
        loadChildren: () => import('./profile/profile.module').then(m => m.ProfilePageModule)
      },
      {
        path: 'system',
        loadChildren: () => import('./system/system.module').then(m => m.SystemPageModule),
        data: { requiresAdmin: true }
      },
      {
        path: '',
        redirectTo: 'terminal',
        pathMatch: 'full'
      }
    ]
  }
];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})
export class DashboardPageRoutingModule {}
