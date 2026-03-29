class SftpFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final String permissions;
  final DateTime modifiedTime;
  final String owner;
  final String group;

  SftpFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.permissions,
    required this.modifiedTime,
    required this.owner,
    required this.group,
  });

  factory SftpFile.fromJson(Map<String, dynamic> json) {
    return SftpFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      isDirectory: json['is_directory'] ?? false,
      size: json['size'] ?? 0,
      permissions: json['permissions'] ?? '',
      modifiedTime: DateTime.tryParse(json['modified_time'] ?? '') ?? DateTime.now(),
      owner: json['owner'] ?? '',
      group: json['group'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'is_directory': isDirectory,
      'size': size,
      'permissions': permissions,
      'modified_time': modifiedTime.toIso8601String(),
      'owner': owner,
      'group': group,
    };
  }
}

class SftpDirectoryContent {
  final String currentPath;
  final List<SftpFile> files;

  SftpDirectoryContent({
    required this.currentPath,
    required this.files,
  });

  factory SftpDirectoryContent.fromJson(Map<String, dynamic> json) {
    return SftpDirectoryContent(
      currentPath: json['current_path'] ?? '',
      files: (json['files'] as List?)
              ?.map((item) => SftpFile.fromJson(item))
              .toList() ??
          [],
    );
  }
}