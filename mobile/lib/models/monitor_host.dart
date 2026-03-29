class MonitorHost {
  final int hostId;
  final String hostname;
  final String name;
  final String os;
  final int uptime;
  final double cpu;
  final int cpuCount;
  final String cpuModel;
  final double memUsed;
  final double memTotal;
  final double diskUsed;
  final double diskTotal;
  final double netRxRate;
  final double netTxRate;
  final double netMonthlyRx;
  final double netMonthlyTx;
  final String lastUpdated;
  final String agentVersion;
  final double netTrafficLimit;
  final String netTrafficCounterMode;
  final double netTrafficUsedAdjustment;
  final String? expirationDate;
  final String? billingPeriod;
  final double billingAmount;
  final String currency;
  final String flag;

  MonitorHost({
    required this.hostId,
    required this.hostname,
    required this.name,
    required this.os,
    required this.uptime,
    required this.cpu,
    required this.cpuCount,
    required this.cpuModel,
    required this.memUsed,
    required this.memTotal,
    required this.diskUsed,
    required this.diskTotal,
    required this.netRxRate,
    required this.netTxRate,
    required this.netMonthlyRx,
    required this.netMonthlyTx,
    required this.lastUpdated,
    required this.agentVersion,
    required this.netTrafficLimit,
    required this.netTrafficCounterMode,
    required this.netTrafficUsedAdjustment,
    this.expirationDate,
    this.billingPeriod,
    required this.billingAmount,
    required this.currency,
    required this.flag,
  });

  factory MonitorHost.fromJson(Map<String, dynamic> json) {
    return MonitorHost(
      hostId: json['host_id'] ?? json['id'] ?? 0,
      hostname: json['hostname'] ?? '',
      name: json['name'] ?? '',
      os: json['os'] ?? '',
      uptime: json['uptime'] ?? 0,
      cpu: (json['cpu'] ?? 0.0).toDouble(),
      cpuCount: json['cpu_count'] ?? 0,
      cpuModel: json['cpu_model'] ?? '',
      memUsed: (json['mem_used'] ?? 0.0).toDouble(),
      memTotal: (json['mem_total'] ?? 0.0).toDouble(),
      diskUsed: (json['disk_used'] ?? 0.0).toDouble(),
      diskTotal: (json['disk_total'] ?? 0.0).toDouble(),
      netRxRate: (json['net_rx_rate'] ?? 0.0).toDouble(),
      netTxRate: (json['net_tx_rate'] ?? 0.0).toDouble(),
      netMonthlyRx: (json['net_monthly_rx'] ?? 0.0).toDouble(),
      netMonthlyTx: (json['net_monthly_tx'] ?? 0.0).toDouble(),
      lastUpdated: json['last_updated'] ?? '',
      agentVersion: json['agent_version'] ?? 'Unknown',
      netTrafficLimit: (json['net_traffic_limit'] ?? 0.0).toDouble(),
      netTrafficCounterMode: json['net_traffic_counter_mode'] ?? 'monthly',
      netTrafficUsedAdjustment: (json['net_traffic_used_adjustment'] ?? 0.0).toDouble(),
      expirationDate: json['expiration_date'],
      billingPeriod: json['billing_period'],
      billingAmount: (json['billing_amount'] ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'USD',
      flag: json['flag'] ?? '🏳️',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host_id': hostId,
      'hostname': hostname,
      'name': name,
      'os': os,
      'uptime': uptime,
      'cpu': cpu,
      'cpu_count': cpuCount,
      'cpu_model': cpuModel,
      'mem_used': memUsed,
      'mem_total': memTotal,
      'disk_used': diskUsed,
      'disk_total': diskTotal,
      'net_rx_rate': netRxRate,
      'net_tx_rate': netTxRate,
      'net_monthly_rx': netMonthlyRx,
      'net_monthly_tx': netMonthlyTx,
      'last_updated': lastUpdated,
      'agent_version': agentVersion,
      'net_traffic_limit': netTrafficLimit,
      'net_traffic_counter_mode': netTrafficCounterMode,
      'net_traffic_used_adjustment': netTrafficUsedAdjustment,
      'expiration_date': expirationDate,
      'billing_period': billingPeriod,
      'billing_amount': billingAmount,
      'currency': currency,
      'flag': flag,
    };
  }

  MonitorHost copyWith({
    int? hostId,
    String? hostname,
    String? name,
    String? os,
    int? uptime,
    double? cpu,
    int? cpuCount,
    String? cpuModel,
    double? memUsed,
    double? memTotal,
    double? diskUsed,
    double? diskTotal,
    double? netRxRate,
    double? netTxRate,
    double? netMonthlyRx,
    double? netMonthlyTx,
    String? lastUpdated,
    String? agentVersion,
    double? netTrafficLimit,
    String? netTrafficCounterMode,
    double? netTrafficUsedAdjustment,
    String? expirationDate,
    String? billingPeriod,
    double? billingAmount,
    String? currency,
    String? flag,
  }) {
    return MonitorHost(
      hostId: hostId ?? this.hostId,
      hostname: hostname ?? this.hostname,
      name: name ?? this.name,
      os: os ?? this.os,
      uptime: uptime ?? this.uptime,
      cpu: cpu ?? this.cpu,
      cpuCount: cpuCount ?? this.cpuCount,
      cpuModel: cpuModel ?? this.cpuModel,
      memUsed: memUsed ?? this.memUsed,
      memTotal: memTotal ?? this.memTotal,
      diskUsed: diskUsed ?? this.diskUsed,
      diskTotal: diskTotal ?? this.diskTotal,
      netRxRate: netRxRate ?? this.netRxRate,
      netTxRate: netTxRate ?? this.netTxRate,
      netMonthlyRx: netMonthlyRx ?? this.netMonthlyRx,
      netMonthlyTx: netMonthlyTx ?? this.netMonthlyTx,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      agentVersion: agentVersion ?? this.agentVersion,
      netTrafficLimit: netTrafficLimit ?? this.netTrafficLimit,
      netTrafficCounterMode: netTrafficCounterMode ?? this.netTrafficCounterMode,
      netTrafficUsedAdjustment: netTrafficUsedAdjustment ?? this.netTrafficUsedAdjustment,
      expirationDate: expirationDate ?? this.expirationDate,
      billingPeriod: billingPeriod ?? this.billingPeriod,
      billingAmount: billingAmount ?? this.billingAmount,
      currency: currency ?? this.currency,
      flag: flag ?? this.flag,
    );
  }
}