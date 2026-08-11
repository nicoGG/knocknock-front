import 'package:equatable/equatable.dart';

enum ListMemberRole { owner, editor }

enum ListBackgroundPreset {
  paper,
  sunrise,
  lagoon,
  botanical,
  lavender,
  midnight,
  ocean,
  desert,
  cherry,
  aurora,
  custom,
}

class ListKeyEnvelope extends Equatable {
  const ListKeyEnvelope({required this.deviceId, required this.envelope});

  factory ListKeyEnvelope.fromJson(Map<String, dynamic> json) =>
      ListKeyEnvelope(
        deviceId: json['deviceId'] as String,
        envelope: json['envelope'] as String,
      );

  final String deviceId;
  final String envelope;

  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'envelope': envelope};

  @override
  List<Object?> get props => [deviceId, envelope];
}

class ListEncryption extends Equatable {
  const ListEncryption({this.version = 0, this.keyEnvelopes = const []});

  factory ListEncryption.fromJson(Map<String, dynamic>? json) => ListEncryption(
    version: (json?['version'] as num?)?.toInt() ?? 0,
    keyEnvelopes: (json?['keyEnvelopes'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ListKeyEnvelope.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  final int version;
  final List<ListKeyEnvelope> keyEnvelopes;

  Map<String, dynamic> toJson() => {
    'version': version,
    'keyEnvelopes': keyEnvelopes.map((entry) => entry.toJson()).toList(),
  };

  @override
  List<Object?> get props => [version, keyEnvelopes];
}

class ListAppearance extends Equatable {
  const ListAppearance({
    this.backgroundPreset = ListBackgroundPreset.paper,
    this.backgroundBlur = 0,
    this.customBackgroundImage,
  });

  factory ListAppearance.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ListAppearance();
    return ListAppearance(
      backgroundPreset: ListBackgroundPreset.values.firstWhere(
        (preset) => preset.name == json['backgroundPreset'],
        orElse: () => ListBackgroundPreset.paper,
      ),
      backgroundBlur: ((json['backgroundBlur'] as num?)?.toDouble() ?? 0)
          .clamp(0, 20)
          .toDouble(),
      customBackgroundImage: json['customBackgroundImage'] as String?,
    );
  }

  final ListBackgroundPreset backgroundPreset;
  final double backgroundBlur;

  /// Base64-encoded, picker-compressed image bytes.
  final String? customBackgroundImage;

  bool get hasCustomBackground =>
      customBackgroundImage != null && customBackgroundImage!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'backgroundPreset': backgroundPreset.name,
    'backgroundBlur': backgroundBlur,
    if (hasCustomBackground) 'customBackgroundImage': customBackgroundImage,
  };

  @override
  List<Object?> get props => [
    backgroundPreset,
    backgroundBlur,
    customBackgroundImage,
  ];
}

enum AggregateBoardScope { assignedToMe, pinned, withReminder }

class AggregateBoardAppearances extends Equatable {
  const AggregateBoardAppearances({
    this.assignedToMe = const ListAppearance(),
    this.pinned = const ListAppearance(),
    this.withReminder = const ListAppearance(),
  });

  factory AggregateBoardAppearances.fromJson(Map<String, dynamic>? json) {
    Map<String, dynamic>? appearance(String key) {
      final value = json?[key];
      return value is Map ? Map<String, dynamic>.from(value) : null;
    }

    return AggregateBoardAppearances(
      assignedToMe: ListAppearance.fromJson(appearance('assignedToMe')),
      pinned: ListAppearance.fromJson(appearance('pinned')),
      withReminder: ListAppearance.fromJson(appearance('withReminder')),
    );
  }

  final ListAppearance assignedToMe;
  final ListAppearance pinned;
  final ListAppearance withReminder;

  ListAppearance forScope(AggregateBoardScope scope) => switch (scope) {
    AggregateBoardScope.assignedToMe => assignedToMe,
    AggregateBoardScope.pinned => pinned,
    AggregateBoardScope.withReminder => withReminder,
  };

  AggregateBoardAppearances copyWithScope(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) => switch (scope) {
    AggregateBoardScope.assignedToMe => AggregateBoardAppearances(
      assignedToMe: appearance,
      pinned: pinned,
      withReminder: withReminder,
    ),
    AggregateBoardScope.pinned => AggregateBoardAppearances(
      assignedToMe: assignedToMe,
      pinned: appearance,
      withReminder: withReminder,
    ),
    AggregateBoardScope.withReminder => AggregateBoardAppearances(
      assignedToMe: assignedToMe,
      pinned: pinned,
      withReminder: appearance,
    ),
  };

  Map<String, dynamic> toJson() => {
    'assignedToMe': assignedToMe.toJson(),
    'pinned': pinned.toJson(),
    'withReminder': withReminder.toJson(),
  };

  @override
  List<Object?> get props => [assignedToMe, pinned, withReminder];
}

class ListCollaborator extends Equatable {
  const ListCollaborator({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.photoUrl,
  });

  factory ListCollaborator.fromJson(Map<String, dynamic> json) =>
      ListCollaborator(
        uid: json['uid'] as String,
        email: json['email'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Colaborador',
        photoUrl: json['photoUrl'] as String?,
        role: ListMemberRole.values.firstWhere(
          (role) => role.name == json['role'],
          orElse: () => ListMemberRole.editor,
        ),
        joinedAt: DateTime.parse(json['joinedAt'] as String),
      );

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final ListMemberRole role;
  final DateTime joinedAt;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    if (photoUrl != null) 'photoUrl': photoUrl,
    'role': role.name,
    'joinedAt': joinedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [
    uid,
    email,
    displayName,
    photoUrl,
    role,
    joinedAt,
  ];
}

class ListPendingInvitation extends Equatable {
  const ListPendingInvitation({required this.email, required this.invitedAt});

  factory ListPendingInvitation.fromJson(Map<String, dynamic> json) =>
      ListPendingInvitation(
        email: json['email'] as String,
        invitedAt: DateTime.parse(json['invitedAt'] as String),
      );

  final String email;
  final DateTime invitedAt;

  Map<String, dynamic> toJson() => {
    'email': email,
    'invitedAt': invitedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [email, invitedAt];
}

class NoteList extends Equatable {
  const NoteList({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.currentUserRole = ListMemberRole.owner,
    this.collaborators = const [],
    this.pendingInvitations = const [],
    this.appearance = const ListAppearance(),
    this.encryption = const ListEncryption(),
  });

  factory NoteList.fromJson(Map<String, dynamic> json) => NoteList(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    currentUserRole: ListMemberRole.values.firstWhere(
      (role) => role.name == json['currentUserRole'],
      orElse: () => ListMemberRole.owner,
    ),
    collaborators: (json['collaborators'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ListCollaborator.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    pendingInvitations:
        (json['pendingInvitations'] as List<dynamic>? ?? const [])
            .map(
              (item) => ListPendingInvitation.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
    appearance: ListAppearance.fromJson(
      json['appearance'] == null
          ? null
          : Map<String, dynamic>.from(json['appearance'] as Map),
    ),
    encryption: ListEncryption.fromJson(
      json['encryption'] == null
          ? null
          : Map<String, dynamic>.from(json['encryption'] as Map),
    ),
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ListMemberRole currentUserRole;
  final List<ListCollaborator> collaborators;
  final List<ListPendingInvitation> pendingInvitations;
  final ListAppearance appearance;
  final ListEncryption encryption;

  bool get canInvite => currentUserRole == ListMemberRole.owner;
  bool get isShared =>
      collaborators.length > 1 || pendingInvitations.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'currentUserRole': currentUserRole.name,
    'collaborators': collaborators.map((person) => person.toJson()).toList(),
    'pendingInvitations': pendingInvitations
        .map((invitation) => invitation.toJson())
        .toList(),
    'appearance': appearance.toJson(),
    'encryption': encryption.toJson(),
  };

  NoteList copyWith({
    String? name,
    DateTime? updatedAt,
    ListAppearance? appearance,
    ListEncryption? encryption,
  }) => NoteList(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    currentUserRole: currentUserRole,
    collaborators: collaborators,
    pendingInvitations: pendingInvitations,
    appearance: appearance ?? this.appearance,
    encryption: encryption ?? this.encryption,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    createdAt,
    updatedAt,
    currentUserRole,
    collaborators,
    pendingInvitations,
    appearance,
    encryption,
  ];
}
