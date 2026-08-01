import '../entities/chat_turn_owner.dart';
import '../entities/skill.dart';
import 'immutable_json_snapshot.dart';

const String canonicalSaveSkillToolName = 'save_skill';

/// Exact identity of one save_skill invocation.
final class SaveSkillOperationIdentity {
  SaveSkillOperationIdentity({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
  }) {
    if (toolCallId.trim().isEmpty) {
      throw ArgumentError.value(
        toolCallId,
        'toolCallId',
        'A non-empty tool call ID is required.',
      );
    }
    if (toolName != canonicalSaveSkillToolName) {
      throw ArgumentError.value(
        toolName,
        'toolName',
        'The canonical save_skill tool name is required.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;

  @override
  bool operator ==(Object other) {
    return other is SaveSkillOperationIdentity &&
        other.owner == owner &&
        other.toolCallId == toolCallId &&
        other.toolName == toolName;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName);
}

/// Immutable save_skill input captured for one exact invocation.
final class SaveSkillToolRequest {
  SaveSkillToolRequest({
    required ChatTurnOwner owner,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) : identity = SaveSkillOperationIdentity(
         owner: owner,
         toolCallId: toolCallId,
         toolName: toolName,
       ),
       arguments = freezeSaveSkillArguments(arguments);

  final SaveSkillOperationIdentity identity;
  final Map<String, dynamic> arguments;

  ChatTurnOwner get owner => identity.owner;
  String get toolCallId => identity.toolCallId;
  String get toolName => identity.toolName;
  String get name => (arguments['name'] as String?)?.trim() ?? '';
  String get description => (arguments['description'] as String?)?.trim() ?? '';
  String get whenToUse => (arguments['when_to_use'] as String?)?.trim() ?? '';
  String get body => (arguments['content'] as String?)?.trim() ?? '';
  String? get reason => (arguments['reason'] as String?)?.trim();
  bool get allowDuplicate => arguments['allow_duplicate'] as bool? ?? false;
}

Map<String, dynamic> freezeSaveSkillArguments(Map<String, dynamic> source) {
  return ImmutableJsonSnapshot.freezeMap(source);
}

/// Immutable skill catalog captured for one exact invocation.
final class SkillStoreSnapshot {
  SkillStoreSnapshot({required this.identity, required List<Skill> skills})
    : skills = List<Skill>.unmodifiable(skills);

  final SaveSkillOperationIdentity identity;
  final List<Skill> skills;
}

final class SkillStoreWriteRequest {
  const SkillStoreWriteRequest({
    required this.existingId,
    required this.markdown,
  });

  final String? existingId;
  final String markdown;
}

enum SkillStoreWriteDisposition {
  committed,
  rejected,
  ownerExpired,
  effectUncertain,
}

/// Durable state left by a write whose owner expired.
enum SkillStoreExpiredWriteDisposition {
  notCommitted,
  compensated,
  retained,
  uncertain,
}

final class SkillStoreWriteResult {
  const SkillStoreWriteResult.committed({
    required this.identity,
    required Skill this.skill,
  }) : disposition = SkillStoreWriteDisposition.committed,
       expiredWriteDisposition = null,
       errorMessage = null;

  const SkillStoreWriteResult.rejected({
    required this.identity,
    required this.errorMessage,
  }) : disposition = SkillStoreWriteDisposition.rejected,
       expiredWriteDisposition = SkillStoreExpiredWriteDisposition.notCommitted,
       skill = null;

  const SkillStoreWriteResult.ownerExpired({
    required this.identity,
    required SkillStoreExpiredWriteDisposition this.expiredWriteDisposition,
  }) : disposition = SkillStoreWriteDisposition.ownerExpired,
       skill = null,
       errorMessage = null;

  const SkillStoreWriteResult.effectUncertain({required this.identity})
    : disposition = SkillStoreWriteDisposition.effectUncertain,
      expiredWriteDisposition = SkillStoreExpiredWriteDisposition.uncertain,
      skill = null,
      errorMessage = null;

  final SaveSkillOperationIdentity identity;
  final SkillStoreWriteDisposition disposition;
  final Skill? skill;
  final SkillStoreExpiredWriteDisposition? expiredWriteDisposition;
  final String? errorMessage;
}

enum SkillSaveAcknowledgementDisposition {
  acknowledged,
  ownerExpired,
  effectUncertain,
}

/// Exact acknowledgement for owner checks and post-write evidence.
final class SkillSaveAcknowledgement {
  const SkillSaveAcknowledgement.acknowledged({required this.identity})
    : disposition = SkillSaveAcknowledgementDisposition.acknowledged;

  const SkillSaveAcknowledgement.ownerExpired({required this.identity})
    : disposition = SkillSaveAcknowledgementDisposition.ownerExpired;

  const SkillSaveAcknowledgement.effectUncertain({required this.identity})
    : disposition = SkillSaveAcknowledgementDisposition.effectUncertain;

  final SaveSkillOperationIdentity identity;
  final SkillSaveAcknowledgementDisposition disposition;
}

final class SkillSaveApprovalRequest {
  const SkillSaveApprovalRequest({
    required this.toolRequest,
    required this.operation,
    required this.path,
    required this.preview,
    required this.reason,
    required this.existingSkill,
  });

  final SaveSkillToolRequest toolRequest;
  final String operation;
  final String path;
  final String preview;
  final String? reason;
  final Skill? existingSkill;
}

final class SkillSaveApprovalDecision {
  const SkillSaveApprovalDecision({
    required this.identity,
    required this.approved,
  });

  final SaveSkillOperationIdentity identity;
  final bool approved;
}

abstract interface class SkillStorePort {
  SkillStoreSnapshot snapshot(SaveSkillOperationIdentity identity);

  Future<SkillStoreWriteResult> upsertMarkdown(
    SaveSkillOperationIdentity identity,
    SkillStoreWriteRequest request,
  );

  Future<SkillSaveAcknowledgement> recordSuccessfulSave(
    SaveSkillOperationIdentity identity,
  );
}

abstract interface class SkillSaveApprovalPort {
  Future<SkillSaveApprovalDecision> requestApproval(
    SkillSaveApprovalRequest request,
  );

  SkillSaveAcknowledgement acknowledgeOwner(
    SaveSkillOperationIdentity identity,
  );
}
