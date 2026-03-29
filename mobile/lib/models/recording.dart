class Recording {
  final int id;
  final String name;
  final String path;
  final int size;
  final String hostName;
  final String userName;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final String status; // active, completed, error

  Recording({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.hostName,
    required this.userName,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.status,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      size: json['size'] ?? 0,
      hostName: json['host_name'] ?? json['hostname'] ?? '',
      userName: json['user_name'] ?? json['username'] ?? '',
      startTime: DateTime.tryParse(json['start_time'] ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(json['end_time'] ?? '') ?? DateTime.now(),
      duration: Duration(
        milliseconds: (json['duration'] ?? 0) * 1000, // Assuming duration is in seconds
      ),
      status: json['status'] ?? 'completed',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'size': size,
      'host_name': hostName,
      'user_name': userName,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'duration': duration.inSeconds,
      'status': status,
    };
  }
}