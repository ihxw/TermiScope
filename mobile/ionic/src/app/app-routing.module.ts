import { NgModule } from '@angular/core';
import { PreloadAllModules, RouterModule, Routes } from '@angular/router';

const routes: Routes = [
  {
    path: 'home',
    loadChildren: () => import('./home/home.module').then(m => m.HomePageModule)
  },
  {
    path: '',
    redirectTo: 'login',
    pathMatch: 'full'
  },
  {
    path: 'login',
    loadChildren: () => import('./login/login.module').then(m => m.LoginPageModule)
  },
  {
    path: 'dashboard',
    loadChildren: () => import('./dashboard/dashboard.module').then(m => m.DashboardPageModule)
  },
  {
    path: 'hosts',
    loadChildren: () => import('./hosts/hosts.module').then(m => m.HostsPageModule)
  },
  {
    path: 'terminal',
    loadChildren: () => import('./terminal/terminal.module').then( m => m.TerminalPageModule)
  },
  {
    path: 'history',
    loadChildren: () => import('./history/history.module').then( m => m.HistoryPageModule)
  },
  {
    path: 'commands',
    loadChildren: () => import('./commands/commands.module').then( m => m.CommandsPageModule)
  },
  {
    path: 'recordings',
    loadChildren: () => import('./recordings/recordings.module').then( m => m.RecordingsPageModule)
  },
  {
    path: 'settings',
    loadChildren: () => import('./settings/settings.module').then( m => m.SettingsPageModule)
  },
  {
    path: 'sftp-browser',
    loadChildren: () => import('./sftp-browser/sftp-browser.module').then( m => m.SftpBrowserPageModule)
  },
  {
    path: 'network-monitor',
    loadChildren: () => import('./network-monitor/network-monitor.module').then( m => m.NetworkMonitorPageModule)
  },
  {
    path: 'profile',
    loadChildren: () => import('./profile/profile.module').then( m => m.ProfilePageModule)
  },
  {
    path: 'user-management',
    loadChildren: () => import('./user-management/user-management.module').then( m => m.UserManagementPageModule)
  },
  {
    path: 'system-settings',
    loadChildren: () => import('./system-settings/system-settings.module').then( m => m.SystemSettingsPageModule)
  },
  {
    path: 'recording-player',
    loadChildren: () => import('./recording-player/recording-player.module').then( m => m.RecordingPlayerPageModule)
  },
  {
    path: 'network-detail',
    loadChildren: () => import('./network-detail/network-detail.module').then( m => m.NetworkDetailPageModule)
  },
];

@NgModule({
  imports: [
    RouterModule.forRoot(routes, { preloadingStrategy: PreloadAllModules })
  ],
  exports: [RouterModule]
})
export class AppRoutingModule { }
