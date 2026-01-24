import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ssh_host.dart';
import '../services/host_service.dart';
import '../services/websocket_service.dart';
import 'auth_provider.dart';

// ============ 主机服务 Provider ============

final hostServiceProvider = Provider<HostService>((ref) {
  final api = ref.watch(apiClientProvider);
  return HostService(api);
});

// ============ WebSocket 服务 Provider ============

final wsServiceProvider = Provider<WebSocketService>((ref) {
  final authService = ref.watch(authServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  return WebSocketService(authService, storage);
});

// ============ 主机列表状态 ============

class HostsState {
  final List<SshHost> hosts;
  final bool isLoading;
  final String? error;
  final Map<int, MonitorData> monitorData;

  HostsState({
    this.hosts = const [],
    this.isLoading = false,
    this.error,
    this.monitorData = const {},
  });

  HostsState copyWith({
    List<SshHost>? hosts,
    bool? isLoading,
    String? error,
    Map<int, MonitorData>? monitorData,
  }) {
    return HostsState(
      hosts: hosts ?? this.hosts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      monitorData: monitorData ?? this.monitorData,
    );
  }

  /// 获取带有实时监控数据的主机列表
  List<SshHost> get hostsWithMonitorData {
    return hosts.map((host) {
      if (monitorData.containsKey(host.id)) {
        return host.copyWith(monitorData: monitorData[host.id]);
      }
      return host;
    }).toList();
  }
}

class HostsNotifier extends StateNotifier<HostsState> {
  final HostService _hostService;
  final WebSocketService _wsService;
  StreamSubscription? _subscription;

  HostsNotifier(this._hostService, this._wsService) : super(HostsState()) {
    // 监听 WebSocket 数据
    _subscription = _wsService.dataStream.listen(
      (data) {
        // 使用 try-catch 包裹整个更新逻辑
        try {
          // 检查是否已经 mounted (通过检查是否能访问 state)
          final _ = state;
          state = state.copyWith(monitorData: data);
        } catch (e) {
          // 忽略任何错误 - 可能是 dispose 后的更新
        }
      },
      onError: (error) {
        // 忽略流错误
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    // 立即取消订阅
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  /// 加载主机列表
  Future<void> loadHosts() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final hosts = await _hostService.getHosts();
      state = state.copyWith(hosts: hosts, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 刷新主机列表
  Future<void> refresh() async {
    await loadHosts();
  }

  /// 连接 WebSocket
  Future<void> connectWebSocket() async {
    await _wsService.connect();
  }

  /// 断开 WebSocket
  void disconnectWebSocket() {
    _wsService.disconnect();
  }

  /// 删除主机
  Future<void> deleteHost(int id) async {
    await _hostService.deleteHost(id);
    state = state.copyWith(
      hosts: state.hosts.where((h) => h.id != id).toList(),
    );
  }

  /// 部署监控
  Future<void> deployMonitor(int id, {bool insecure = false}) async {
    await _hostService.deployMonitor(id, insecure: insecure);
    await loadHosts();
  }

  /// 停止监控
  Future<void> stopMonitor(int id) async {
    await _hostService.stopMonitor(id);
    await loadHosts();
  }

  /// 批量部署监控
  Future<void> batchDeployMonitor(List<int> hostIds,
      {bool insecure = false}) async {
    await _hostService.batchDeployMonitor(hostIds, insecure: insecure);
    await loadHosts();
  }

  /// 批量停止监控
  Future<void> batchStopMonitor(List<int> hostIds) async {
    await _hostService.batchStopMonitor(hostIds);
    await loadHosts();
  }
}

final hostsStateProvider =
    StateNotifierProvider<HostsNotifier, HostsState>((ref) {
  final hostService = ref.watch(hostServiceProvider);
  final wsService = ref.watch(wsServiceProvider);
  return HostsNotifier(hostService, wsService);
});
