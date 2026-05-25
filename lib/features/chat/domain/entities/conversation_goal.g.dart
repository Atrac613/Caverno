// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_goal.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationGoal _$ConversationGoalFromJson(Map<String, dynamic> json) =>
    _ConversationGoal(
      id: json['id'] as String,
      objective: json['objective'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      status:
          $enumDecodeNullable(
            _$ConversationGoalStatusEnumMap,
            json['status'],
            unknownValue: ConversationGoalStatus.active,
          ) ??
          ConversationGoalStatus.active,
      tokenBudget: (json['tokenBudget'] as num?)?.toInt() ?? 0,
      tokenUsage: (json['tokenUsage'] as num?)?.toInt() ?? 0,
      turnBudget: (json['turnBudget'] as num?)?.toInt() ?? 0,
      turnsUsed: (json['turnsUsed'] as num?)?.toInt() ?? 0,
      completionSummary: json['completionSummary'] as String? ?? '',
      blockedReason: json['blockedReason'] as String? ?? '',
      blockerSignature: json['blockerSignature'] as String? ?? '',
      blockerRepeatCount: (json['blockerRepeatCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      blockedAt: json['blockedAt'] == null
          ? null
          : DateTime.parse(json['blockedAt'] as String),
      lastBlockerSeenAt: json['lastBlockerSeenAt'] == null
          ? null
          : DateTime.parse(json['lastBlockerSeenAt'] as String),
    );

Map<String, dynamic> _$ConversationGoalToJson(_ConversationGoal instance) =>
    <String, dynamic>{
      'id': instance.id,
      'objective': instance.objective,
      'enabled': instance.enabled,
      'status': _$ConversationGoalStatusEnumMap[instance.status]!,
      'tokenBudget': instance.tokenBudget,
      'tokenUsage': instance.tokenUsage,
      'turnBudget': instance.turnBudget,
      'turnsUsed': instance.turnsUsed,
      'completionSummary': instance.completionSummary,
      'blockedReason': instance.blockedReason,
      'blockerSignature': instance.blockerSignature,
      'blockerRepeatCount': instance.blockerRepeatCount,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'completedAt': instance.completedAt?.toIso8601String(),
      'blockedAt': instance.blockedAt?.toIso8601String(),
      'lastBlockerSeenAt': instance.lastBlockerSeenAt?.toIso8601String(),
    };

const _$ConversationGoalStatusEnumMap = {
  ConversationGoalStatus.active: 'active',
  ConversationGoalStatus.completed: 'completed',
  ConversationGoalStatus.blocked: 'blocked',
};
