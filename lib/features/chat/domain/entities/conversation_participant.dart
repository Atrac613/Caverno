import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../settings/domain/entities/app_settings.dart';

part 'conversation_participant.freezed.dart';
part 'conversation_participant.g.dart';

enum ParticipantTurnDepth { singleRound, multiRound }

enum ParticipantTurnPolicy { roundRobin }

@freezed
abstract class ParticipantTurnConfig with _$ParticipantTurnConfig {
  const factory ParticipantTurnConfig({
    @JsonKey(unknownEnumValue: ParticipantTurnPolicy.roundRobin)
    @Default(ParticipantTurnPolicy.roundRobin)
    ParticipantTurnPolicy turnPolicy,
    @JsonKey(unknownEnumValue: ParticipantTurnDepth.singleRound)
    @Default(ParticipantTurnDepth.singleRound)
    ParticipantTurnDepth depth,
    @Default(2) int maxRounds,
  }) = _ParticipantTurnConfig;

  factory ParticipantTurnConfig.fromJson(Map<String, dynamic> json) =>
      _$ParticipantTurnConfigFromJson(json);
}

@freezed
abstract class ConversationParticipant with _$ConversationParticipant {
  const ConversationParticipant._();

  const factory ConversationParticipant({
    required String id,
    @Default('') String displayName,
    @Default('') String roleLabel,
    @Default('') String roleSystemPrompt,
    @Default('') String endpointId,
    @Default('') String model,
    @Default(false) bool facilitatesTurns,
    @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)
    @Default(ToolApprovalMode.defaultPermissions)
    ToolApprovalMode toolApprovalMode,
    @Default(false) bool toolsEnabled,
    @Default(0xFF6750A4) int colorValue,
    @Default(0) int order,
    @Default(true) bool enabled,
  }) = _ConversationParticipant;

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) =>
      _$ConversationParticipantFromJson(json);

  bool get isPrimary => endpointId.trim().isEmpty;

  bool get isTurnFacilitator {
    if (facilitatesTurns) {
      return true;
    }
    final normalizedRole = effectiveRoleLabel.toLowerCase();
    return normalizedRole.contains('facilitator') ||
        normalizedRole.contains('moderator');
  }

  String get effectiveDisplayName {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? 'Assistant' : trimmed;
  }

  String get effectiveRoleLabel {
    final trimmed = roleLabel.trim();
    return trimmed.isEmpty ? 'Assistant' : trimmed;
  }
}
