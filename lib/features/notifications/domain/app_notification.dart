import 'package:equatable/equatable.dart';

enum AppNotificationType {
  collaboratorJoined,
  noteCreated,
  noteUpdated,
  noteDeleted,
  taskAssigned,
  reminder,
}

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final typeName = (json['type'] as String? ?? '').replaceAllMapped(
      RegExp(r'_([a-z])'),
      (match) => match.group(1)!.toUpperCase(),
    );
    return AppNotification(
      id: json['id'] as String,
      type: AppNotificationType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => AppNotificationType.noteUpdated,
      ),
      title: json['title'] as String? ?? 'NockNock',
      body: json['body'] as String? ?? '',
      data: Map<String, String>.from(json['data'] as Map? ?? const {}),
      readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final Map<String, String> data;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  AppNotification markRead(DateTime value) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    readAt: value,
    createdAt: createdAt,
  );

  AppNotification copyWith({String? title, String? body}) => AppNotification(
    id: id,
    type: type,
    title: title ?? this.title,
    body: body ?? this.body,
    data: data,
    readAt: readAt,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [id, type, title, body, data, readAt, createdAt];
}
