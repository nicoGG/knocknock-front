import 'package:equatable/equatable.dart';

enum NoteColor {
  none,
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

enum ReminderRecurrenceFrequency { daily, weekly, monthly }

class ReminderRecurrence extends Equatable {
  const ReminderRecurrence({
    required this.frequency,
    required this.interval,
    required this.timeZoneOffsetMinutes,
    this.timeZoneId,
    this.dayOfMonth,
  });

  factory ReminderRecurrence.fromJson(Map<String, dynamic> json) =>
      ReminderRecurrence(
        frequency: ReminderRecurrenceFrequency.values.firstWhere(
          (frequency) => frequency.name == json['frequency'],
          orElse: () => ReminderRecurrenceFrequency.daily,
        ),
        interval: ((json['interval'] as num?)?.toInt() ?? 1)
            .clamp(1, 99)
            .toInt(),
        timeZoneOffsetMinutes:
            ((json['timeZoneOffsetMinutes'] as num?)?.toInt() ?? 0)
                .clamp(-840, 840)
                .toInt(),
        timeZoneId: (json['timeZoneId'] as String?)?.trim().isNotEmpty == true
            ? (json['timeZoneId'] as String).trim()
            : null,
        dayOfMonth: (json['dayOfMonth'] as num?)?.toInt().clamp(1, 31).toInt(),
      );

  final ReminderRecurrenceFrequency frequency;
  final int interval;
  final int timeZoneOffsetMinutes;
  final String? timeZoneId;
  final int? dayOfMonth;

  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
    'timeZoneOffsetMinutes': timeZoneOffsetMinutes,
    if (timeZoneId != null) 'timeZoneId': timeZoneId,
    'dayOfMonth': dayOfMonth,
  };

  @override
  List<Object?> get props => [
    frequency,
    interval,
    timeZoneOffsetMinutes,
    timeZoneId,
    dayOfMonth,
  ];
}

const supportedNoteReactionEmojis = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '😍',
  '🤔',
  '🤯',
  '😡',
  '🐶',
  '🐱',
  '🐵',
  '🐷',
  '🎉',
  '👏',
  '🙌',
  '🔥',
  '👀',
  '💯',
  '🚀',
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

List<NoteAttachment> _attachmentsFromJson(Map<String, dynamic> json) {
  final rawAttachments = json['attachments'];
  if (rawAttachments is List) {
    return rawAttachments
        .whereType<Map>()
        .map((item) => NoteAttachment.fromJson(Map<String, dynamic>.from(item)))
        .take(2)
        .toList(growable: false);
  }
  final legacy = json['attachment'];
  return legacy is Map
      ? [NoteAttachment.fromJson(Map<String, dynamic>.from(legacy))]
      : const [];
}

DateTime? _localDateTimeFromJson(Object? value) {
  final parsed = DateTime.tryParse(value as String? ?? '');
  return parsed?.toLocal();
}

String reminderDateTimeToJson(DateTime value) =>
    value.toUtc().toIso8601String();

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
    this.attachments = const [],
    NoteAttachment? attachment,
    this.reminderAt,
    this.reminderRecurrence,
    this.contentDelta,
    this.revision = 0,
    this.deletedAt,
  }) : _legacyAttachment = attachment;

  factory Note.fromJson(Map<String, dynamic> json) {
    final rawRecurrence = json['reminderRecurrence'];
    final reminderRecurrence = rawRecurrence is Map
        ? ReminderRecurrence.fromJson(Map<String, dynamic>.from(rawRecurrence))
        : null;
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
      attachments: _attachmentsFromJson(json),
      isCompleted: reminderRecurrence == null
          ? json['isCompleted'] as bool? ?? false
          : false,
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
      reminderAt: _localDateTimeFromJson(json['reminderAt']),
      reminderRecurrence: reminderRecurrence,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      deletedAt: _localDateTimeFromJson(json['deletedAt']),
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
  final List<NoteAttachment> attachments;
  final NoteAttachment? _legacyAttachment;
  List<NoteAttachment> get photoAttachments => attachments.isNotEmpty
      ? attachments
      : _legacyAttachment == null
      ? const []
      : [_legacyAttachment];
  NoteAttachment? get attachment => photoAttachments.firstOrNull;
  final bool isCompleted;
  final bool isPinned;
  final int sortOrder;
  final NoteCategory category;
  final List<NoteChecklistItem> checklist;
  final List<NoteReaction> reactions;
  final double positionX;
  final double positionY;
  final DateTime? reminderAt;
  final ReminderRecurrence? reminderRecurrence;
  bool get isRecurring => reminderAt != null && reminderRecurrence != null;
  final int revision;
  final DateTime? deletedAt;
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
    'attachments': photoAttachments.map((entry) => entry.toJson()).toList(),
    'isCompleted': isCompleted,
    'isPinned': isPinned,
    'sortOrder': sortOrder,
    'category': category.name,
    'checklist': checklist.map((item) => item.toJson()).toList(),
    'reactions': reactions.map((reaction) => reaction.toJson()).toList(),
    'positionX': positionX,
    'positionY': positionY,
    if (reminderAt != null) 'reminderAt': reminderDateTimeToJson(reminderAt!),
    if (reminderRecurrence != null)
      'reminderRecurrence': reminderRecurrence!.toJson(),
    'revision': revision,
    if (deletedAt != null) 'deletedAt': reminderDateTimeToJson(deletedAt!),
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
    List<NoteAttachment>? attachments,
    DateTime? updatedAt,
    int? revision,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
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
    attachments: attachments ?? photoAttachments,
    isCompleted: reminderRecurrence == null
        ? isCompleted ?? this.isCompleted
        : false,
    isPinned: isPinned ?? this.isPinned,
    sortOrder: sortOrder ?? this.sortOrder,
    category: category ?? this.category,
    checklist: checklist ?? this.checklist,
    reactions: reactions ?? this.reactions,
    positionX: positionX,
    positionY: positionY,
    reminderAt: reminderAt,
    reminderRecurrence: reminderRecurrence,
    revision: revision ?? this.revision,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
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
    photoAttachments,
    isCompleted,
    isPinned,
    sortOrder,
    category,
    checklist,
    reactions,
    positionX,
    positionY,
    reminderAt,
    reminderRecurrence,
    revision,
    deletedAt,
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
    this.attachments = const [],
    NoteAttachment? attachment,
    this.reminderAt,
    this.reminderRecurrence,
    this.contentDelta,
    this.clientNoteId,
    this.clientMutationId,
    this.isCompleted = false,
    this.isPinned = false,
    this.sortOrder,
    this.positionX = 0,
    this.positionY = 0,
  }) : _legacyAttachment = attachment;

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
    attachments: _attachmentsFromJson(json),
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
    reminderAt: _localDateTimeFromJson(json['reminderAt']),
    reminderRecurrence: json['reminderRecurrence'] is Map
        ? ReminderRecurrence.fromJson(
            Map<String, dynamic>.from(json['reminderRecurrence'] as Map),
          )
        : null,
    clientNoteId: json['clientNoteId'] as String?,
    clientMutationId: json['clientMutationId'] as String?,
    isCompleted: json['reminderRecurrence'] is Map
        ? false
        : json['isCompleted'] as bool? ?? false,
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
  final List<NoteAttachment> attachments;
  final NoteAttachment? _legacyAttachment;
  List<NoteAttachment> get photoAttachments => attachments.isNotEmpty
      ? attachments
      : _legacyAttachment == null
      ? const []
      : [_legacyAttachment];
  NoteAttachment? get attachment => photoAttachments.firstOrNull;
  final NoteCategory category;
  final List<NoteChecklistItem> checklist;
  final DateTime? reminderAt;
  final ReminderRecurrence? reminderRecurrence;
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
    attachments: photoAttachments,
    category: category,
    checklist: checklist,
    reminderAt: reminderAt,
    reminderRecurrence: reminderRecurrence,
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
    'attachments': photoAttachments.map((entry) => entry.toJson()).toList(),
    'category': category.name,
    'checklist': checklist.map((item) => item.toJson()).toList(),
    if (reminderAt != null) 'reminderAt': reminderDateTimeToJson(reminderAt!),
    if (reminderRecurrence != null)
      'reminderRecurrence': reminderRecurrence!.toJson(),
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
    photoAttachments,
    category,
    checklist,
    reminderAt,
    reminderRecurrence,
    clientNoteId,
    clientMutationId,
    isCompleted,
    isPinned,
    sortOrder,
    positionX,
    positionY,
  ];
}
