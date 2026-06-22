// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_participant.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ParticipantTurnConfig _$ParticipantTurnConfigFromJson(
  Map<String, dynamic> json,
) => _ParticipantTurnConfig(
  turnPolicy:
      $enumDecodeNullable(
        _$ParticipantTurnPolicyEnumMap,
        json['turnPolicy'],
        unknownValue: ParticipantTurnPolicy.roundRobin,
      ) ??
      ParticipantTurnPolicy.roundRobin,
  depth:
      $enumDecodeNullable(
        _$ParticipantTurnDepthEnumMap,
        json['depth'],
        unknownValue: ParticipantTurnDepth.singleRound,
      ) ??
      ParticipantTurnDepth.singleRound,
  maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 2,
);

Map<String, dynamic> _$ParticipantTurnConfigToJson(
  _ParticipantTurnConfig instance,
) => <String, dynamic>{
  'turnPolicy': _$ParticipantTurnPolicyEnumMap[instance.turnPolicy]!,
  'depth': _$ParticipantTurnDepthEnumMap[instance.depth]!,
  'maxRounds': instance.maxRounds,
};

const _$ParticipantTurnPolicyEnumMap = {
  ParticipantTurnPolicy.roundRobin: 'roundRobin',
};

const _$ParticipantTurnDepthEnumMap = {
  ParticipantTurnDepth.singleRound: 'singleRound',
  ParticipantTurnDepth.multiRound: 'multiRound',
};

_ConversationParticipant _$ConversationParticipantFromJson(
  Map<String, dynamic> json,
) => _ConversationParticipant(
  id: json['id'] as String,
  displayName: json['displayName'] as String? ?? '',
  roleLabel: json['roleLabel'] as String? ?? '',
  roleSystemPrompt: json['roleSystemPrompt'] as String? ?? '',
  endpointId: json['endpointId'] as String? ?? '',
  model: json['model'] as String? ?? '',
  toolApprovalMode:
      $enumDecodeNullable(
        _$ToolApprovalModeEnumMap,
        json['toolApprovalMode'],
        unknownValue: ToolApprovalMode.defaultPermissions,
      ) ??
      ToolApprovalMode.defaultPermissions,
  toolsEnabled: json['toolsEnabled'] as bool? ?? false,
  colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF6750A4,
  order: (json['order'] as num?)?.toInt() ?? 0,
  enabled: json['enabled'] as bool? ?? true,
);

Map<String, dynamic> _$ConversationParticipantToJson(
  _ConversationParticipant instance,
) => <String, dynamic>{
  'id': instance.id,
  'displayName': instance.displayName,
  'roleLabel': instance.roleLabel,
  'roleSystemPrompt': instance.roleSystemPrompt,
  'endpointId': instance.endpointId,
  'model': instance.model,
  'toolApprovalMode': _$ToolApprovalModeEnumMap[instance.toolApprovalMode]!,
  'toolsEnabled': instance.toolsEnabled,
  'colorValue': instance.colorValue,
  'order': instance.order,
  'enabled': instance.enabled,
};

const _$ToolApprovalModeEnumMap = {
  ToolApprovalMode.defaultPermissions: 'defaultPermissions',
  ToolApprovalMode.autoReview: 'autoReview',
  ToolApprovalMode.fullAccess: 'fullAccess',
};
