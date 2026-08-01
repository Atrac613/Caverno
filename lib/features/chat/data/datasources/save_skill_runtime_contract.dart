import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/skill.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/immutable_json_snapshot.dart';
import '../../domain/services/save_skill_tool_handler.dart';

typedef SaveSkillSnapshotCallback =
    SaveSkillSnapshotAcknowledgement Function(
      SaveSkillRuntimeIdentity identity,
    );
typedef SaveSkillFreshManualApprovalCallback =
    Future<SaveSkillApprovalAcknowledgement> Function(
      SaveSkillRuntimeApprovalRequest request,
    );
typedef SaveSkillOwnerCallback =
    SaveSkillOwnerAcknowledgement Function(SaveSkillRuntimeIdentity identity);
typedef SaveSkillWriteCallback =
    Future<SaveSkillWriteAcknowledgement> Function(
      SaveSkillRuntimeWriteRequest request,
    );
typedef SaveSkillCompensationCallback =
    Future<SaveSkillCompensationAcknowledgement> Function(
      SaveSkillCompensationRequest request,
    );
typedef SaveSkillSuccessCallback =
    Future<SaveSkillSuccessAcknowledgement> Function(
      SaveSkillSuccessIdentity identity,
    );
typedef SaveSkillSuccessReconciliationCallback =
    Future<SaveSkillSuccessAcknowledgement> Function(
      SaveSkillSuccessIdentity identity,
    );

/// Exact immutable identity for one save_skill invocation.
final class SaveSkillRuntimeIdentity {
  SaveSkillRuntimeIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _required(toolCallId, 'toolCallId'),
       toolName = _canonicalToolName(toolName),
       argumentDigest = _required(argumentDigest, 'argumentDigest');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;

  @override
  bool operator ==(Object other) =>
      other is SaveSkillRuntimeIdentity &&
      other.owner == owner &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      other.argumentDigest == argumentDigest;

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

/// Strict input captured before any asynchronous approval or store callback.
final class SaveSkillRuntimeInput {
  factory SaveSkillRuntimeInput({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) {
    final arguments = ImmutableJsonSnapshot.freezeMap(toolCall.arguments);
    return SaveSkillRuntimeInput._(
      identity: SaveSkillRuntimeIdentity(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        argumentDigest: saveSkillJsonDigest(arguments),
      ),
      arguments: arguments,
    );
  }

  const SaveSkillRuntimeInput._({
    required this.identity,
    required this.arguments,
  });

  final SaveSkillRuntimeIdentity identity;
  final Map<String, dynamic> arguments;

  SaveSkillToolRequest toToolRequest() => SaveSkillToolRequest(
    owner: identity.owner,
    toolCallId: identity.toolCallId,
    toolName: identity.toolName,
    arguments: arguments,
  );
}

/// Invocation plus the exact catalog snapshot used to build the preview.
final class SaveSkillCatalogIdentity {
  SaveSkillCatalogIdentity({
    required this.runtime,
    required String catalogDigest,
  }) : catalogDigest = _required(catalogDigest, 'catalogDigest');

  final SaveSkillRuntimeIdentity runtime;
  final String catalogDigest;

  @override
  bool operator ==(Object other) =>
      other is SaveSkillCatalogIdentity &&
      other.runtime == runtime &&
      other.catalogDigest == catalogDigest;

  @override
  int get hashCode => Object.hash(runtime, catalogDigest);
}

enum SaveSkillSnapshotDisposition { captured, rejected, effectUncertain }

final class SaveSkillSnapshotAcknowledgement {
  SaveSkillSnapshotAcknowledgement.captured({
    required this.identity,
    required List<Skill> skills,
  }) : disposition = SaveSkillSnapshotDisposition.captured,
       skills = List<Skill>.unmodifiable(skills);

  const SaveSkillSnapshotAcknowledgement.rejected({required this.identity})
    : disposition = SaveSkillSnapshotDisposition.rejected,
      skills = null;

  const SaveSkillSnapshotAcknowledgement.effectUncertain({
    required this.identity,
  }) : disposition = SaveSkillSnapshotDisposition.effectUncertain,
       skills = null;

  final SaveSkillRuntimeIdentity identity;
  final SaveSkillSnapshotDisposition disposition;
  final List<Skill>? skills;
}

final class SaveSkillRuntimeApprovalRequest {
  const SaveSkillRuntimeApprovalRequest({
    required this.identity,
    required this.request,
  });

  final SaveSkillCatalogIdentity identity;
  final SkillSaveApprovalRequest request;
}

enum SaveSkillApprovalDisposition {
  approved,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class SaveSkillApprovalAcknowledgement {
  const SaveSkillApprovalAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final SaveSkillCatalogIdentity identity;
  final SaveSkillApprovalDisposition disposition;
}

enum SaveSkillOwnerDisposition { current, ownerExpired, effectUncertain }

final class SaveSkillOwnerAcknowledgement {
  const SaveSkillOwnerAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final SaveSkillRuntimeIdentity identity;
  final SaveSkillOwnerDisposition disposition;
}

final class SaveSkillRuntimeWriteRequest {
  SaveSkillRuntimeWriteRequest({
    required SaveSkillCatalogIdentity catalog,
    required this.request,
  }) : identity = SaveSkillMutationIdentity(
         catalog: catalog,
         writeDigest: saveSkillWriteDigest(request),
       );

  final SaveSkillMutationIdentity identity;
  final SkillStoreWriteRequest request;
}

/// Catalog and write payload bound to one exact compensable mutation.
final class SaveSkillMutationIdentity {
  SaveSkillMutationIdentity({
    required this.catalog,
    required String writeDigest,
  }) : writeDigest = _required(writeDigest, 'writeDigest');

  final SaveSkillCatalogIdentity catalog;
  final String writeDigest;

  @override
  bool operator ==(Object other) =>
      other is SaveSkillMutationIdentity &&
      other.catalog == catalog &&
      other.writeDigest == writeDigest;

  @override
  int get hashCode => Object.hash(catalog, writeDigest);
}

enum SaveSkillWriteDisposition {
  committed,
  rejectedBeforeEffect,
  ownerExpiredBeforeEffect,
  ownerExpiredAfterEffect,
  effectUncertainAfterEffect,
}

final class SaveSkillWriteAcknowledgement {
  SaveSkillWriteAcknowledgement.committed({
    required this.identity,
    required this.skill,
    required String compensationToken,
  }) : disposition = SaveSkillWriteDisposition.committed,
       compensationToken = _required(compensationToken, 'compensationToken'),
       errorMessage = null;

  SaveSkillWriteAcknowledgement.rejectedBeforeEffect({
    required this.identity,
    required String errorMessage,
  }) : disposition = SaveSkillWriteDisposition.rejectedBeforeEffect,
       skill = null,
       compensationToken = null,
       errorMessage = _required(errorMessage, 'errorMessage');

  const SaveSkillWriteAcknowledgement.ownerExpiredBeforeEffect({
    required this.identity,
  }) : disposition = SaveSkillWriteDisposition.ownerExpiredBeforeEffect,
       skill = null,
       compensationToken = null,
       errorMessage = null;

  SaveSkillWriteAcknowledgement.ownerExpiredAfterEffect({
    required this.identity,
    required String compensationToken,
  }) : disposition = SaveSkillWriteDisposition.ownerExpiredAfterEffect,
       skill = null,
       compensationToken = _required(compensationToken, 'compensationToken'),
       errorMessage = null;

  SaveSkillWriteAcknowledgement.effectUncertainAfterEffect({
    required this.identity,
    required String compensationToken,
    required String errorMessage,
  }) : disposition = SaveSkillWriteDisposition.effectUncertainAfterEffect,
       skill = null,
       compensationToken = _required(compensationToken, 'compensationToken'),
       errorMessage = _required(errorMessage, 'errorMessage');

  final SaveSkillMutationIdentity identity;
  final SaveSkillWriteDisposition disposition;
  final Skill? skill;
  final String? compensationToken;
  final String? errorMessage;
}

final class SaveSkillCompensationRequest {
  SaveSkillCompensationRequest({
    required this.identity,
    required String compensationToken,
  }) : compensationToken = _required(compensationToken, 'compensationToken');

  final SaveSkillMutationIdentity identity;
  final String compensationToken;
}

enum SaveSkillCompensationDisposition {
  compensated,
  alreadyAbsent,
  retained,
  effectUncertain,
}

final class SaveSkillCompensationAcknowledgement {
  SaveSkillCompensationAcknowledgement({
    required this.identity,
    required String compensationToken,
    required this.disposition,
  }) : compensationToken = _required(compensationToken, 'compensationToken');

  final SaveSkillMutationIdentity identity;
  final String compensationToken;
  final SaveSkillCompensationDisposition disposition;
}

/// Write receipt identity used when recording turn-level save success.
final class SaveSkillSuccessIdentity {
  SaveSkillSuccessIdentity({
    required this.mutation,
    required String compensationToken,
    required String savedSkillDigest,
  }) : compensationToken = _required(compensationToken, 'compensationToken'),
       savedSkillDigest = _required(savedSkillDigest, 'savedSkillDigest');

  final SaveSkillMutationIdentity mutation;
  final String compensationToken;
  final String savedSkillDigest;

  @override
  bool operator ==(Object other) =>
      other is SaveSkillSuccessIdentity &&
      other.mutation == mutation &&
      other.compensationToken == compensationToken &&
      other.savedSkillDigest == savedSkillDigest;

  @override
  int get hashCode =>
      Object.hash(mutation, compensationToken, savedSkillDigest);
}

enum SaveSkillSuccessDisposition { acknowledged, ownerExpired, effectUncertain }

final class SaveSkillSuccessAcknowledgement {
  const SaveSkillSuccessAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final SaveSkillSuccessIdentity identity;
  final SaveSkillSuccessDisposition disposition;
}

enum SaveSkillRuntimeDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
  boundaryMismatch,
}

final class SaveSkillRuntimeCompletion {
  const SaveSkillRuntimeCompletion({
    required this.identity,
    required this.disposition,
    required this.result,
  });

  final SaveSkillRuntimeIdentity identity;
  final SaveSkillRuntimeDisposition disposition;
  final McpToolResult result;
}

String saveSkillJsonDigest(Object? value) {
  final frozen = ImmutableJsonSnapshot.freezeValue(value);
  return sha256
      .convert(utf8.encode(jsonEncode(_canonicalJson(frozen))))
      .toString();
}

String saveSkillCatalogDigest(List<Skill> skills) {
  final entries =
      [
        for (final skill in skills)
          <String, Object?>{
            'id': skill.id,
            'name': skill.name,
            'description': skill.description,
            'whenToUse': skill.whenToUse,
            'content': skill.content,
            'enabled': skill.enabled,
            'createdAt': skill.createdAt.toUtc().toIso8601String(),
            'updatedAt': skill.updatedAt.toUtc().toIso8601String(),
          },
      ]..sort(
        (left, right) => jsonEncode(
          _canonicalJson(left),
        ).compareTo(jsonEncode(_canonicalJson(right))),
      );
  return saveSkillJsonDigest(entries);
}

String saveSkillDigest(Skill skill) => saveSkillCatalogDigest([skill]);

String saveSkillWriteDigest(SkillStoreWriteRequest request) =>
    saveSkillJsonDigest({
      'existingId': request.existingId,
      'markdown': request.markdown,
    });

String _required(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return value;
}

String _canonicalToolName(String value) {
  if (value != canonicalSaveSkillToolName) {
    throw ArgumentError.value(
      value,
      'toolName',
      'toolName must be exactly $canonicalSaveSkillToolName.',
    );
  }
  return value;
}

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalJson).toList(growable: false);
  return value;
}
