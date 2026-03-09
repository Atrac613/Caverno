enum MemoryEntryType { preference, persona, topic, constraint }

class MemoryEntry {
  MemoryEntry({
    required this.id,
    required this.text,
    required this.type,
    required this.confidence,
    required this.importance,
    required this.updatedAt,
    this.sourceConversationId,
    this.expiresAt,
  });

  final String id;
  final String text;
  final MemoryEntryType type;
  final double confidence;
  final double importance;
  final DateTime updatedAt;
  final String? sourceConversationId;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  MemoryEntry copyWith({
    String? id,
    String? text,
    MemoryEntryType? type,
    double? confidence,
    double? importance,
    DateTime? updatedAt,
    String? sourceConversationId,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) {
    return MemoryEntry(
      id: id ?? this.id,
      text: text ?? this.text,
      type: type ?? this.type,
      confidence: confidence ?? this.confidence,
      importance: importance ?? this.importance,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceConversationId: sourceConversationId ?? this.sourceConversationId,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
    );
  }

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? '';
    final type = MemoryEntryType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => MemoryEntryType.topic,
    );
    return MemoryEntry(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      type: type,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceConversationId: json['sourceConversationId'] as String?,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'type': type.name,
      'confidence': confidence,
      'importance': importance,
      'updatedAt': updatedAt.toIso8601String(),
      'sourceConversationId': sourceConversationId,
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }
}

class MemorySessionSummary {
  MemorySessionSummary({
    required this.conversationId,
    required this.summary,
    required this.openLoops,
    required this.updatedAt,
  });

  final String conversationId;
  final String summary;
  final List<String> openLoops;
  final DateTime updatedAt;

  MemorySessionSummary copyWith({
    String? conversationId,
    String? summary,
    List<String>? openLoops,
    DateTime? updatedAt,
  }) {
    return MemorySessionSummary(
      conversationId: conversationId ?? this.conversationId,
      summary: summary ?? this.summary,
      openLoops: openLoops ?? this.openLoops,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory MemorySessionSummary.fromJson(Map<String, dynamic> json) {
    return MemorySessionSummary(
      conversationId: json['conversationId'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      openLoops: _stringList(json['openLoops']),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'conversationId': conversationId,
      'summary': summary,
      'openLoops': openLoops,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class UserMemoryProfile {
  UserMemoryProfile({
    required this.persona,
    required this.preferences,
    required this.doNot,
    required this.updatedAt,
  });

  factory UserMemoryProfile.empty() {
    return UserMemoryProfile(
      persona: const [],
      preferences: const [],
      doNot: const [],
      updatedAt: DateTime.now(),
    );
  }

  final List<String> persona;
  final List<String> preferences;
  final List<String> doNot;
  final DateTime updatedAt;

  bool get isEmpty => persona.isEmpty && preferences.isEmpty && doNot.isEmpty;

  UserMemoryProfile copyWith({
    List<String>? persona,
    List<String>? preferences,
    List<String>? doNot,
    DateTime? updatedAt,
  }) {
    return UserMemoryProfile(
      persona: persona ?? this.persona,
      preferences: preferences ?? this.preferences,
      doNot: doNot ?? this.doNot,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory UserMemoryProfile.fromJson(Map<String, dynamic> json) {
    return UserMemoryProfile(
      persona: _stringList(json['persona']),
      preferences: _stringList(json['preferences']),
      doNot: _stringList(json['doNot']),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'persona': persona,
      'preferences': preferences,
      'doNot': doNot,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return raw.whereType<String>().map((v) => v.trim()).where((v) {
      return v.isNotEmpty;
    }).toList();
  }
  return const [];
}
