import 'dart:convert';

enum RemoteCodingConnectionStatus {
  disconnected,
  connecting,
  connected,
  pairing,
  error,
}

enum RemoteCodingApprovalKind { file, localCommand, gitCommand }

class RemoteCodingServerSettings {
  const RemoteCodingServerSettings({
    this.enabled = false,
    this.port = 8767,
    this.pairedDevices = const <RemoteCodingPairedDevice>[],
  });

  final bool enabled;
  final int port;
  final List<RemoteCodingPairedDevice> pairedDevices;

  factory RemoteCodingServerSettings.fromJson(Map<String, dynamic> json) {
    return RemoteCodingServerSettings(
      enabled: json['enabled'] == true,
      port: (json['port'] as num?)?.toInt() ?? 8767,
      pairedDevices:
          (json['pairedDevices'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RemoteCodingPairedDevice.fromJson)
              .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'port': port,
    'pairedDevices': pairedDevices.map((device) => device.toJson()).toList(),
  };

  RemoteCodingServerSettings copyWith({
    bool? enabled,
    int? port,
    List<RemoteCodingPairedDevice>? pairedDevices,
  }) {
    return RemoteCodingServerSettings(
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      pairedDevices: pairedDevices ?? this.pairedDevices,
    );
  }
}

class RemoteCodingPairedDevice {
  const RemoteCodingPairedDevice({
    required this.id,
    required this.name,
    required this.tokenHash,
    required this.createdAt,
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final String tokenHash;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  factory RemoteCodingPairedDevice.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return RemoteCodingPairedDevice(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? 'Mobile device',
      tokenHash: (json['tokenHash'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? now,
      lastSeenAt:
          DateTime.tryParse((json['lastSeenAt'] as String?) ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tokenHash': tokenHash,
    'createdAt': createdAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
  };

  RemoteCodingPairedDevice copyWith({
    String? id,
    String? name,
    String? tokenHash,
    DateTime? createdAt,
    DateTime? lastSeenAt,
  }) {
    return RemoteCodingPairedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      tokenHash: tokenHash ?? this.tokenHash,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

class RemoteCodingHost {
  const RemoteCodingHost({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get websocketUrl => 'ws://$host:$port/ws';

  factory RemoteCodingHost.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return RemoteCodingHost(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? 'Caverno Desktop',
      host: (json['host'] as String?)?.trim() ?? '',
      port: (json['port'] as num?)?.toInt() ?? 8767,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? now,
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class RemoteCodingPairingPayload {
  const RemoteCodingPairingPayload({
    required this.ticketId,
    required this.secret,
    required this.host,
    required this.port,
    required this.expiresAt,
    required this.serverName,
  });

  static const kind = 'caverno_remote_coding_v1';

  final String ticketId;
  final String secret;
  final String host;
  final int port;
  final DateTime expiresAt;
  final String serverName;

  String get websocketUrl => 'ws://$host:$port/ws';

  String toQrData() => jsonEncode({
    'kind': kind,
    'ticketId': ticketId,
    'secret': secret,
    'host': host,
    'port': port,
    'expiresAt': expiresAt.toIso8601String(),
    'serverName': serverName,
  });

  factory RemoteCodingPairingPayload.fromQrData(String value) {
    final decoded = jsonDecode(value.trim());
    if (decoded is! Map<String, dynamic> || decoded['kind'] != kind) {
      throw const FormatException(
        'QR code is not a Caverno remote coding pair code.',
      );
    }
    final expiresAt = DateTime.tryParse(
      (decoded['expiresAt'] as String?) ?? '',
    );
    if (expiresAt == null) {
      throw const FormatException('Pairing code has an invalid expiry.');
    }
    return RemoteCodingPairingPayload(
      ticketId: (decoded['ticketId'] as String?)?.trim() ?? '',
      secret: (decoded['secret'] as String?)?.trim() ?? '',
      host: (decoded['host'] as String?)?.trim() ?? '',
      port: (decoded['port'] as num?)?.toInt() ?? 8767,
      expiresAt: expiresAt,
      serverName:
          (decoded['serverName'] as String?)?.trim() ?? 'Caverno Desktop',
    );
  }
}

class RemoteCodingApproval {
  const RemoteCodingApproval({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.detail,
    this.reason,
    this.warningTitle,
    this.warningMessage,
  });

  final String id;
  final RemoteCodingApprovalKind kind;
  final String title;
  final String subtitle;
  final String detail;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;

  factory RemoteCodingApproval.fromJson(Map<String, dynamic> json) {
    final kindName = (json['kind'] as String?)?.trim() ?? '';
    return RemoteCodingApproval(
      id: (json['id'] as String?)?.trim() ?? '',
      kind: switch (kindName) {
        'localCommand' => RemoteCodingApprovalKind.localCommand,
        'gitCommand' => RemoteCodingApprovalKind.gitCommand,
        _ => RemoteCodingApprovalKind.file,
      },
      title: (json['title'] as String?)?.trim() ?? 'Approval required',
      subtitle: (json['subtitle'] as String?)?.trim() ?? '',
      detail: (json['detail'] as String?) ?? '',
      reason: json['reason'] as String?,
      warningTitle: json['warningTitle'] as String?,
      warningMessage: json['warningMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': switch (kind) {
      RemoteCodingApprovalKind.file => 'file',
      RemoteCodingApprovalKind.localCommand => 'localCommand',
      RemoteCodingApprovalKind.gitCommand => 'gitCommand',
    },
    'title': title,
    'subtitle': subtitle,
    'detail': detail,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
    if (warningTitle != null && warningTitle!.isNotEmpty)
      'warningTitle': warningTitle,
    if (warningMessage != null && warningMessage!.isNotEmpty)
      'warningMessage': warningMessage,
  };
}

class RemoteCodingQuestionOption {
  const RemoteCodingQuestionOption({
    required this.id,
    required this.label,
    this.description = '',
    this.preview = '',
  });

  final String id;
  final String label;
  final String description;
  final String preview;

  factory RemoteCodingQuestionOption.fromJson(Map<String, dynamic> json) {
    return RemoteCodingQuestionOption(
      id: (json['id'] as String?)?.trim() ?? '',
      label: (json['label'] as String?)?.trim() ?? '',
      description: (json['description'] as String?)?.trim() ?? '',
      preview: (json['preview'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    if (description.isNotEmpty) 'description': description,
    if (preview.isNotEmpty) 'preview': preview,
  };
}

/// A pending `ask_user_question` mirrored to a remote client. Distinct from
/// [RemoteCodingApproval] because a question carries selectable options, an
/// optional free-text answer, and single/multi-select semantics rather than a
/// binary approve/deny.
class RemoteCodingQuestion {
  const RemoteCodingQuestion({
    required this.id,
    required this.question,
    this.help = '',
    this.options = const <RemoteCodingQuestionOption>[],
    this.allowMultiple = false,
    this.allowOther = true,
    this.otherPlaceholder = '',
  });

  final String id;
  final String question;
  final String help;
  final List<RemoteCodingQuestionOption> options;
  final bool allowMultiple;
  final bool allowOther;
  final String otherPlaceholder;

  factory RemoteCodingQuestion.fromJson(Map<String, dynamic> json) {
    return RemoteCodingQuestion(
      id: (json['id'] as String?)?.trim() ?? '',
      question: (json['question'] as String?)?.trim() ?? '',
      help: (json['help'] as String?)?.trim() ?? '',
      options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(RemoteCodingQuestionOption.fromJson)
          .toList(growable: false),
      allowMultiple: json['allowMultiple'] == true,
      allowOther: json['allowOther'] != false,
      otherPlaceholder: (json['otherPlaceholder'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    if (help.isNotEmpty) 'help': help,
    'options': options.map((option) => option.toJson()).toList(),
    'allowMultiple': allowMultiple,
    'allowOther': allowOther,
    if (otherPlaceholder.isNotEmpty) 'otherPlaceholder': otherPlaceholder,
  };
}

class RemoteCodingProjectSummary {
  const RemoteCodingProjectSummary({
    required this.id,
    required this.name,
    required this.rootPath,
  });

  final String id;
  final String name;
  final String rootPath;

  factory RemoteCodingProjectSummary.fromJson(Map<String, dynamic> json) {
    return RemoteCodingProjectSummary(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? 'Project',
      rootPath: (json['rootPath'] as String?)?.trim() ?? '',
    );
  }
}

class RemoteCodingThreadSummary {
  const RemoteCodingThreadSummary({
    required this.id,
    required this.title,
    required this.projectId,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? projectId;
  final DateTime updatedAt;

  factory RemoteCodingThreadSummary.fromJson(Map<String, dynamic> json) {
    return RemoteCodingThreadSummary(
      id: (json['id'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim() ?? 'New thread',
      projectId: (json['projectId'] as String?)?.trim(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
