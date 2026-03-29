class SSHHost {
  final int id;
  final String name;
  final String hostname;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final String? fingerprint;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  SSHHost({
    required this.id,
    required this.name,
    required this.hostname,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.fingerprint,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SSHHost.fromJson(Map<String, dynamic> json) {
    return SSHHost(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      hostname: json['hostname'] ?? '',
      port: json['port'] ?? 22,
      username: json['username'] ?? '',
      password: json['password'],
      privateKey: json['private_key'],
      passphrase: json['passphrase'],
      fingerprint: json['fingerprint'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'hostname': hostname,
      'port': port,
      'username': username,
      'password': password,
      'private_key': privateKey,
      'passphrase': passphrase,
      'fingerprint': fingerprint,
      'is_active': isActive,
    };
  }

  SSHHost copyWith({
    int? id,
    String? name,
    String? hostname,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? passphrase,
    String? fingerprint,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SSHHost(
      id: id ?? this.id,
      name: name ?? this.name,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      fingerprint: fingerprint ?? this.fingerprint,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}