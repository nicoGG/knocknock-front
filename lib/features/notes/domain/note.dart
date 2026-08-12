import 'package:equatable/equatable.dart';

enum NoteColor {
  yellow,
  pink,
  blue,
  green,
  purple,
  orange,
  mint,
  coral,
  gray,
  red,
  teal,
  brown,
}

enum NoteCategory {
  general,
  personal,
  work,
  shopping,
  health,
  travel,
  study,
  finance,
  money,
  home,
  ideas,
}

const supportedNoteReactionEmojis = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🎉',
  '👏',
  '🙌',
  '😍',
  '🤔',
  '🔥',
  '👀',
  '🤯',
  '💯',
  '🚀',
  '😡',
  '🐶',
  '🐱',
  '🐵',
  '🐼',
  '🍕',
  '🍔',
  '✈️',
  '✅',
  '💪',
];
const localNoteReactionUserId = 'local-device';

class NoteReaction extends Equatable {
  const NoteReaction({required this.emoji, this.userUids = const []});

  factory NoteReaction.fromJson(Map<String, dynamic> json) => NoteReaction(
    emoji: json['emoji'] as String,
    userUids: (json['userUids'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet()
        .toList(),
  );

  final String emoji;
  final List<String> userUids;

  int get count => userUids.length;

  bool isSelectedBy(String? userUid) =>
      userUids.contains(userUid ?? localNoteReactionUserId);

  Map<String, dynamic> toJson() => {'emoji': emoji, 'userUids': userUids};

  @override
  List<Object?> get props => [emoji, userUids];
}

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

class NoteAttachment extends Equatable {
  const NoteAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    this.dataBase64,
  });

  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Adjunto',
    mimeType: json['mimeType'] as String? ?? 'application/pdf',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    dataBase64: json['dataBase64'] as String?,
  );

  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? dataBase64;

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    if (dataBase64 != null) 'dataBase64': dataBase64,
  };

  NoteAttachment copyWith({String? name, String? dataBase64}) => NoteAttachment(
    id: id,
    name: name ?? this.name,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    dataBase64: dataBase64 ?? this.dataBase64,
  );

  @override
  List<Object?> get props => [id, name, mimeType, sizeBytes, dataBase64];
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
    this.reactions = const [],
    this.assigneeUid,
    this.customAssigneeName,
    this.attachment,
    this.reminderAt,
    this.contentDelta,
    this.revision = 0,
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
      customAssigneeName: json['customAssigneeName'] as String?,
      attachment: json['attachment'] is Map
          ? NoteAttachment.fromJson(
              Map<String, dynamic>.from(json['attachment'] as Map),
            )
          : null,
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
      reactions: (json['reactions'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                NoteReaction.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .where((reaction) => reaction.count > 0)
          .toList(),
      positionX: (json['positionX'] as num?)?.toDouble() ?? 0,
      positionY: (json['positionY'] as num?)?.toDouble() ?? 0,
      reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
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
  final String? customAssigneeName;
  final NoteAttachment? attachment;
  final bool isCompleted;
  final bool isPinned;
  final int sortOrder;
  final NoteCategory category;
  final List<NoteChecklistItem> checklist;
  final List<NoteReaction> reactions;
  final double positionX;
  final double positionY;
  final DateTime? reminderAt;
  final int revision;
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
    if (customAssigneeName != null) 'customAssigneeName': customAssigneeName,
    if (attachment != null) 'attachment': attachment!.toJson(),
    'isCompleted': isCompleted,
    'isPinned': isPinned,
    'sortOrder': sortOrder,
    'category': category.name,
    'checklist': checklist.map((item) => item.toJson()).toList(),
    'reactions': reactions.map((reaction) => reaction.toJson()).toList(),
    'positionX': positionX,
    'positionY': positionY,
    if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
    'revision': revision,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Note copyWith({
    bool? isCompleted,
    bool? isPinned,
    int? sortOrder,
    NoteCategory? category,
    List<NoteChecklistItem>? checklist,
    List<NoteReaction>? reactions,
    DateTime? updatedAt,
    int? revision,
  }) => Note(
    id: id,
    boardId: boardId,
    title: title,
    content: content,
    contentDelta: contentDelta,
    color: color,
    authorName: authorName,
    assigneeUid: assigneeUid,
    customAssigneeName: customAssigneeName,
    attachment: attachment,
    isCompleted: isCompleted ?? this.isCompleted,
    isPinned: isPinned ?? this.isPinned,
    sortOrder: sortOrder ?? this.sortOrder,
    category: category ?? this.category,
    checklist: checklist ?? this.checklist,
    reactions: reactions ?? this.reactions,
    positionX: positionX,
    positionY: positionY,
    reminderAt: reminderAt,
    revision: revision ?? this.revision,
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
    customAssigneeName,
    attachment,
    isCompleted,
    isPinned,
    sortOrder,
    category,
    checklist,
    reactions,
    positionX,
    positionY,
    reminderAt,
    revision,
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
    this.customAssigneeName,
    this.attachment,
    this.reminderAt,
    this.contentDelta,
    this.clientNoteId,
    this.clientMutationId,
    this.isCompleted = false,
    this.isPinned = false,
    this.sortOrder,
    this.positionX = 0,
    this.positionY = 0,
  });

  factory NoteDraft.fromJson(Map<String, dynamic> json) => NoteDraft(
    title: json['title'] as String,
    content: json['content'] as String? ?? '',
    contentDelta: json['contentDelta'] as String?,
    color: NoteColor.values.firstWhere(
      (color) => color.name == json['color'],
      orElse: () => NoteColor.yellow,
    ),
    authorName: json['authorName'] as String? ?? 'Invitado',
    assigneeUid: json['assigneeUid'] as String?,
    customAssigneeName: json['customAssigneeName'] as String?,
    attachment: json['attachment'] is Map
        ? NoteAttachment.fromJson(
            Map<String, dynamic>.from(json['attachment'] as Map),
          )
        : null,
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
    reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
    clientNoteId: json['clientNoteId'] as String?,
    clientMutationId: json['clientMutationId'] as String?,
    isCompleted: json['isCompleted'] as bool? ?? false,
    isPinned: json['isPinned'] as bool? ?? false,
    sortOrder: (json['sortOrder'] as num?)?.toInt(),
    positionX: (json['positionX'] as num?)?.toDouble() ?? 0,
    positionY: (json['positionY'] as num?)?.toDouble() ?? 0,
  );

  final String title;
  final String content;
  final String? contentDelta;
  final NoteColor color;
  final String authorName;
  final String? assigneeUid;
  final String? customAssigneeName;
  final NoteAttachment? attachment;
  final NoteCategory category;
  final List<NoteChecklistItem> checklist;
  final DateTime? reminderAt;
  final String? clientNoteId;
  final String? clientMutationId;
  final bool isCompleted;
  final bool isPinned;
  final int? sortOrder;
  final double positionX;
  final double positionY;

  NoteDraft withSyncContext({
    required String clientNoteId,
    required String clientMutationId,
  }) => NoteDraft(
    title: title,
    content: content,
    contentDelta: contentDelta,
    color: color,
    authorName: authorName,
    assigneeUid: assigneeUid,
    customAssigneeName: customAssigneeName,
    attachment: attachment,
    category: category,
    checklist: checklist,
    reminderAt: reminderAt,
    clientNoteId: clientNoteId,
    clientMutationId: clientMutationId,
    isCompleted: isCompleted,
    isPinned: isPinned,
    sortOrder: sortOrder,
    positionX: positionX,
    positionY: positionY,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    if (contentDelta != null) 'contentDelta': contentDelta,
    'color': color.name,
    'authorName': authorName,
    if (assigneeUid != null) 'assigneeUid': assigneeUid,
    if (customAssigneeName != null) 'customAssigneeName': customAssigneeName,
    if (attachment != null) 'attachment': attachment!.toJson(),
    'category': category.name,
    'checklist': checklist.map((item) => item.toJson()).toList(),
    if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
    if (clientNoteId != null) 'clientNoteId': clientNoteId,
    if (clientMutationId != null) 'clientMutationId': clientMutationId,
    'isCompleted': isCompleted,
    'isPinned': isPinned,
    if (sortOrder != null) 'sortOrder': sortOrder,
    'positionX': positionX,
    'positionY': positionY,
  };

  @override
  List<Object?> get props => [
    title,
    content,
    contentDelta,
    color,
    authorName,
    assigneeUid,
    customAssigneeName,
    attachment,
    category,
    checklist,
    reminderAt,
    clientNoteId,
    clientMutationId,
    isCompleted,
    isPinned,
    sortOrder,
    positionX,
    positionY,
  ];
}
