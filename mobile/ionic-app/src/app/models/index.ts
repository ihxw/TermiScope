export interface User {
  id: number;
  username: string;
  email?: string;
  role: 'admin' | 'user';
  is_active: boolean;
  created_at?: string;
  updated_at?: string;
}

export interface LoginResponse {
  token: string;
  refresh_token: string;
  user: User;
  requires_2fa?: boolean;
  user_id?: number;
  temp_token?: string;
}

export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error?: string;
}

export interface SSHHost {
  id: number;
  name: string;
  host: string;
  port: number;
  username: string;
  password?: string;
  private_key?: string;
  auth_type: 'password' | 'key';
  description?: string;
  group?: string;
  tags?: string[];
  is_active: boolean;
  fingerprint?: string;
  created_at?: string;
  updated_at?: string;
}

export interface MonitorStatus {
  id: number;
  host_id: number;
  status: 'running' | 'stopped' | 'error';
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  network_rx: number;
  network_tx: number;
  last_updated: string;
}

export interface NetworkLatency {
  id: number;
  host_id: number;
  latency_ms: number;
  packet_loss: number;
  tested_at: string;
}

export interface ConnectionLog {
  id: number;
  user_id: number;
  host_id: number;
  host_name: string;
  username: string;
  connected_at: string;
  disconnected_at?: string;
  duration?: number;
  status: 'connected' | 'disconnected' | 'error';
  error_message?: string;
}

export interface Command {
  id: number;
  name: string;
  command: string;
  description?: string;
  category?: string;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
}

export interface Recording {
  id: number;
  session_id: string;
  host_id: number;
  host_name: string;
  username: string;
  user_id: number;
  started_at: string;
  ended_at?: string;
  duration?: number;
  file_size?: number;
  file_path?: string;
}

export interface SystemInfo {
  version: string;
  initialized: boolean;
}

export interface UpdateInfo {
  update_available: boolean;
  version?: string;
  download_url?: string;
  body?: string;
}

export interface UpdateStatus {
  status: 'downloading' | 'extracting' | 'installing' | 'restarting' | 'finished' | 'error';
  error?: string;
}

export interface SFTPFile {
  name: string;
  path: string;
  size: number;
  is_dir: boolean;
  modified_time: string;
  permissions: string;
}

export interface TwoFASetup {
  secret: string;
  qr_code: string;
  backup_codes: string[];
}

// Extended SSHHost with additional fields from Web
export interface SSHHostExtended extends SSHHost {
  host_type?: 'control' | 'monitor';
  expiration_date?: string;
  billing_period?: string;
  billing_amount?: number;
  flag?: string;
  notify_offline?: boolean;
  notify_traffic?: boolean;
  offline_threshold?: number;
  traffic_threshold?: number;
  notify_channels?: string[];
  sort_order?: number;
  deleted_at?: string;
  os?: string;
  agent_version?: string;
}

// Monitor Status Extended
export interface MonitorStatusExtended {
  host_id: number;
  timestamp?: number;
  agent_version?: string;
  agent_update_status?: string;
  uptime?: number;
  cpu?: number;
  cpu_count?: number;
  cpu_model?: string;
  cpu_mhz?: number;
  mem_used?: number;
  mem_total?: number;
  disk_used?: number;
  disk_total?: number;
  disks?: DiskData[];
  net_rx?: number;
  net_tx?: number;
  net_rx_rate?: number;
  net_tx_rate?: number;
  net_monthly_rx?: number;
  net_monthly_tx?: number;
  net_traffic_limit?: number;
  net_traffic_used_adjustment?: number;
  net_traffic_counter_mode?: string;
  interfaces?: MonitorInterface[];
  os?: string;
  hostname?: string;
  last_updated?: number;
  _clientLastUpdated?: number;
  status?: string;
}

export interface DiskData {
  mount_point: string;
  used: number;
  total: number;
}

export interface MonitorInterface {
  name: string;
  rx: number;
  tx: number;
  ips?: string[];
  mac?: string;
  rx_rate?: number;
  tx_rate?: number;
}

// Network Template
export interface NetworkTemplate {
  id: number;
  name: string;
  description?: string;
  target_type: 'ip' | 'domain';
  target_address: string;
  target_port: number;
  frequency: number;
  created_by?: number;
  created_at?: string;
  updated_at?: string;
}

// Network Task
export interface NetworkTask {
  id: number;
  host_id: number;
  name: string;
  target_type: 'ip' | 'domain';
  target_address: string;
  target_port: number;
  frequency: number;
  enabled: boolean;
  created_at?: string;
  updated_at?: string;
}

// Network Task Stats
export interface NetworkTaskStats {
  task_id: number;
  data: {
    timestamp: string;
    latency_ms: number;
    packet_loss: number;
    status: 'success' | 'failed';
  }[];
}

// Traffic Config
export interface TrafficConfig {
  host_id: number;
  primary_interface?: string;
  selected_interfaces?: string[];
  reset_day: number;
  monthly_limit_gb: number;
  already_used_gb: number;
  counter_mode: 'total' | 'tx' | 'rx';
}

// System Settings
export interface SystemSettings {
  ssh_timeout: number;
  idle_timeout: number;
  max_connections_per_user: number;
  login_rate_limit: number;
  access_expiration: number;
  refresh_expiration: number;
  chart_color: string;
  timezone: string;
}

// Notification Settings
export interface NotificationSettings {
  smtp_server?: string;
  smtp_port?: number;
  smtp_user?: string;
  smtp_password?: string;
  smtp_from?: string;
  smtp_to?: string;
  smtp_tls_skip_verify?: boolean;
  telegram_token?: string;
  telegram_chat_id?: string;
  notification_template?: string;
}

// Login History
export interface LoginHistory {
  id: number;
  user_id: number;
  username: string;
  ip_address: string;
  device_info?: string;
  browser?: string;
  os?: string;
  location?: string;
  login_time: string;
  last_active?: string;
  status: 'active' | 'revoked' | 'expired';
  jti?: string;
  is_current?: boolean;
}

// Session
export interface Session {
  jti: string;
  user_id: number;
  username: string;
  ip_address: string;
  browser?: string;
  os?: string;
  location?: string;
  last_active: string;
  status: 'active' | 'revoked' | 'expired';
  is_current?: boolean;
}

// Traffic Reset Log
export interface TrafficResetLog {
  id: number;
  host_id: number;
  host_name: string;
  reset_date: string;
  reset_time: string;
  status: string;
}

// WebSocket Monitor Data
export interface MonitorWebSocketData {
  type: 'status' | 'latency' | 'error';
  host_id: number;
  data: any;
  timestamp: string;
}
