import 'package:equatable/equatable.dart';

enum NoteColor { yellow, pink, blue, green, purple }

enum NoteCategory { general, personal, work, shopping, health, travel }

class NoteChecklistItem extends Equatable {
  const NoteChecklistItem({
    required this.id,
    required this.text,
    this.isCompleted = false,
    this.indent = 0,
  });

  factory NoteChecklistItem.fromJson(Map<String, dynamic> json) =>
      NoteChecklistItem(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
        isCompleted: json['isCompleted'] as bool? ?? false,
        indent: ((json['indent'] as num?)?.toInt() ?? 0).clamp(0, 2).toInt(),
      );

  final String id;
  final String text;
  final bool isCompleted;
  final int indent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isCompleted': isCompleted,
    'indent': indent,
  };

  NoteChecklistItem copyWith({String? text, bool? isCompleted, int? indent}) =>
      NoteChecklistItem(
        id: id,
        text: text ?? this.text,
        isCompleted: isCompleted ?? this.isCompleted,
        indent: indent ?? this.indent,
      );

  @override
  List<Object?> get props => [id, text, isCompleted, indent];
}

List<NoteChecklistItem> normalizeNoteChecklist(
  Iterable<NoteChecklistItem> items, {
  bool trimText = false,
  bool removeEmpty = false,
}) {
  final normalized = <NoteChecklistItem>[];
  for (final item in items) {
    final text = trimText ? item.text.trim() : item.text;
    if (removeEmpty && text.isEmpty) continue;
    final previousIndent = normalized.isEmpty ? -1 : normalized.last.indent;
    final maxIndent = (previousIndent + 1).clamp(0, 2);
    normalized.add(
      item.copyWith(
        text: text,
        indent: item.indent.clamp(0, maxIndent).toInt(),
      ),
    );
  }
  return normalized;
}

int compareNotes(Note a, Note b) {
  if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
  final orderComparison = a.sortOrder.compareTo(b.sortOrder);
  if (orderComparison != 0) return orderComparison;
  final updatedComparison = b.updatedAt.compareTo(a.updatedAt);
  if (updatedComparison != 0) return updatedComparison;
  return a.id.compareTo(b.id);
}

class Note extends Equatable {
  const Note({
    required this.id,
    required this.boardId,
    required this.title,
    required this.content,
    required this.color,
    required this.authorName,
    required this.isCompleted,
    required this.positionX,
    required this.positionY,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.sortOrder = 0,
    this.category = NoteCategory.general,
    this.checklist = const [],
    this.assigneeUid,
    this.reminderAt,
    this.contentDelta,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      boardId: json['boardId'] as String,
      title: json['title'] as String,
      content: json['content'] as String? ?? '',
      contentDelta: json['contentDelta'] as String?,
      color: NoteColor.values.firstWhere(
        (color) => color.name == json['color'],
        orElse: () => NoteColor.yellow,
      ),
      authorName: json['authorName'] as String? ?? 'Invitado',
      assigneeUid: json['assigneeUid'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      category: NoteCategory.values.firstWhere(
        (category) => category.name == json['category'],
        orElse: () => NoteCategory.general,
      ),
      checklist: (json['checklist'] as List<dynamic>? ?? const [])
          .map(
            (item) => NoteChecklistItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0,
      reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final String boardId;
  final String title;
  final String content;
  final String? contentDelta;
  final NoteColor color;
  final String authorName;
  final String? assigneeUid;
  final bool isCompleted;
  final bool isPinned;
  final int sortOrder;
  final NoteCategory category;
  final List<NoteChecklistItem> checklist;
  final double positionX;
  final double positionY;
  final DateTime? reminderAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'boardId': boardId,
    'title': title,
    'content': content,
    if (contentDelta != null) 'contentDelta': contentDelta,
    'color': color.name,
    'authorName': authorName,
    if (assigneeUid != null) 'assigneeUid': assigneeUid,
    'isCompleted': isCompleted,
    'isPinned': isPinned,
    'sortOrder': sortOrder,
    'category': category.name,
    'checklist': checklist.map((item) => item.toJson()).toList(),
    'positionX': positionX,
    'positionY': positionY,
    if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Note copyWith({
    bool? isCompleted,
    bool? isPinned,
    int? sortOrder,
    NoteCategory? category,
    List<NoteChecklistItem>? checklist,
    DateTime? updatedAt,
  }) => Note(
    id: id,
    boardId: boardId,
    title: title,
    content: content,
    contentDelta: contentDelta,
    color: color,
    authorName: authorName,
    assigneeUid: assigneeUid,
    isCompleted: isCompleted ?? this.isCompleted,
    isPinned: isPinned ?? this.isPinned,
    sortOrder: sortOrder ?? this.sortOrder,
    category: category ?? this.category,
    checklist: checklist ?? this.checklist,
    positionX: positionX,
    positionY: positionY,
    reminderAt: reminderAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    boardId,
    title,
    content,
    contentDelta,
    color,
    authorName,
    assigneeUid,
    isCompleted,
    isPinned,
    sortOrder,
    category,
    checklist,
    positionX,
    positionY,
    reminderAt,
    createdAt,
    updatedAt,
  ];
}

class NoteDraft extends Equatable {
  const NoteDraft({
    required this.title,
    required this.content,
    required this.color,
    required this.authorName,
    this.category = NoteCategory.general,
    this.checklist = const [],
    this.assigneeUid,
    this.reminderAt,
    this.contentDelta,
  });

  final String title;
  final String content;
  final String? contentDelta;
  final NoteColor color;
  final String authorName;
  final String? assigneeUid;
  final NoteCategory category;
  final List<NoteChecklistItem> checklist;
  final DateTime? reminderAt;

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    if (contentDelta != null) 'contentDelta': contentDelta,
    'color': color.name,
    'authorName': authorName,
    if (assigneeUid != null) 'assigneeUid': assigneeUid,
    'category': category.name,
    'checklist': checklist.map((item) => item.toJson()).toList(),
    if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
  };

  @override
  List<Object?> get props => [
    title,
    content,
    contentDelta,
    color,
    authorName,
    assigneeUid,
    category,
    checklist,
    reminderAt,
  ];
}
