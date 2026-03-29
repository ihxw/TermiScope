class CommandTemplate {
  final int id;
  final String name;
  final String command;
  final String description;
  final String category;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  CommandTemplate({
    required this.id,
    required this.name,
    required this.command,
    required this.description,
    required this.category,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommandTemplate.fromJson(Map<String, dynamic> json) {
    return CommandTemplate(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      command: json['command'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? 'general',
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'command': command,
      'description': description,
      'category': category,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CommandTemplate copyWith({
    int? id,
    String? name,
    String? command,
    String? description,
    String? category,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CommandTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      description: description ?? this.description,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}