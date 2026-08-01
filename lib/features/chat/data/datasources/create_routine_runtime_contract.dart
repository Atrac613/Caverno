import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../routines/domain/entities/routine.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/create_routine_tool_handler.dart';
import '../../domain/services/immutable_json_snapshot.dart';

typedef CreateRoutineApprovalCallback =
    Future<CreateRoutineApprovalAcknowledgement> Function(
      CreateRoutineRuntimeIdentity identity,
      RoutineCreationApprovalRequest request,
    );
typedef CreateRoutineOwnerCallback =
    CreateRoutineOwnerAcknowledgement Function(
      CreateRoutineRuntimeIdentity identity,
    );
typedef CreateRoutineStoreCallback =
    Future<CreateRoutineStoreAcknowledgement> Function(
      CreateRoutineRuntimeIdentity identity,
      RoutineStoreCreateRequest request,
    );
typedef CreateRoutineSnapshotCallback =
    CreateRoutineSnapshotAcknowledgement Function(
      CreateRoutineReceiptIdentity identity,
    );
typedef CreateRoutineCompensationCallback =
    Future<CreateRoutineCompensationAcknowledgement> Function(
      CreateRoutineReceiptIdentity identity,
    );
typedef CreateRoutineSuccessCallback =
    Future<CreateRoutineSuccessAcknowledgement> Function(
      CreateRoutineSuccessIdentity identity,
    );
typedef CreateRoutineSuccessReleaseCallback =
    Future<CreateRoutineSuccessReleaseAcknowledgement> Function(
      CreateRoutineSuccessIdentity identity,
    );

/// Exact identity for one immutable routine-creation invocation.
final class CreateRoutineRuntimeIdentity {
  CreateRoutineRuntimeIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _canonicalToolName(toolName),
       argumentDigest = _requiredValue(argumentDigest, 'argumentDigest');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;

  bool belongsTo(CreateRoutineRuntimeIdentity expected) => this == expected;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreateRoutineRuntimeIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.argumentDigest == argumentDigest;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

/// Exact receipt identity spanning owner, call, parsed request, and write.
final class CreateRoutineReceiptIdentity {
  CreateRoutineReceiptIdentity({
    required this.runtime,
    required String compensationToken,
    required String requestDigest,
    required String createdRoutineDigest,
  }) : compensationToken = _requiredValue(
         compensationToken,
         'compensationToken',
       ),
       requestDigest = _requiredValue(requestDigest, 'requestDigest'),
       createdRoutineDigest = _requiredValue(
         createdRoutineDigest,
         'createdRoutineDigest',
       );

  final CreateRoutineRuntimeIdentity runtime;
  final String compensationToken;
  final String requestDigest;
  final String createdRoutineDigest;

  @override
  bool operator ==(Object other) =>
      other is CreateRoutineReceiptIdentity &&
      other.runtime == runtime &&
      other.compensationToken == compensationToken &&
      other.requestDigest == requestDigest &&
      other.createdRoutineDigest == createdRoutineDigest;

  @override
  int get hashCode => Object.hash(
    runtime,
    compensationToken,
    requestDigest,
    createdRoutineDigest,
  );
}

/// Strict immutable input captured before any asynchronous runtime callback.
final class CreateRoutineRuntimeInput {
  factory CreateRoutineRuntimeInput({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
  }) {
    final arguments = ImmutableJsonSnapshot.freezeMap(toolCall.arguments);
    return CreateRoutineRuntimeInput._(
      identity: CreateRoutineRuntimeIdentity(
        owner: owner,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        argumentDigest: _argumentDigest(arguments),
      ),
      arguments: arguments,
    );
  }

  const CreateRoutineRuntimeInput._({
    required this.identity,
    required this.arguments,
  });

  final CreateRoutineRuntimeIdentity identity;
  final Map<String, dynamic> arguments;

  CreateRoutineToolRequest toToolRequest() => CreateRoutineToolRequest(
    owner: identity.owner,
    toolCallId: identity.toolCallId,
    toolName: identity.toolName,
    arguments: arguments,
  );
}

enum CreateRoutineApprovalDisposition {
  approved,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class CreateRoutineApprovalAcknowledgement {
  const CreateRoutineApprovalAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final CreateRoutineRuntimeIdentity identity;
  final CreateRoutineApprovalDisposition disposition;
}

enum CreateRoutineOwnerDisposition { current, ownerExpired, effectUncertain }

final class CreateRoutineOwnerAcknowledgement {
  const CreateRoutineOwnerAcknowledgement.current({required this.identity})
    : disposition = CreateRoutineOwnerDisposition.current,
      expiredResult = null;

  const CreateRoutineOwnerAcknowledgement.ownerExpired({
    required this.identity,
    this.expiredResult,
  }) : disposition = CreateRoutineOwnerDisposition.ownerExpired;

  const CreateRoutineOwnerAcknowledgement.effectUncertain({
    required this.identity,
  }) : disposition = CreateRoutineOwnerDisposition.effectUncertain,
       expiredResult = null;

  final CreateRoutineRuntimeIdentity identity;
  final CreateRoutineOwnerDisposition disposition;
  final McpToolResult? expiredResult;
}

enum CreateRoutineStoreDisposition {
  committed,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class CreateRoutineStoreAcknowledgement {
  CreateRoutineStoreAcknowledgement.committed({
    required this.identity,
    required this.receiptIdentity,
    required this.createdRoutine,
  }) : disposition = CreateRoutineStoreDisposition.committed,
       errorMessage = null {
    _validateReceipt();
  }

  const CreateRoutineStoreAcknowledgement.rejected({
    required this.identity,
    this.errorMessage,
  }) : disposition = CreateRoutineStoreDisposition.rejected,
       receiptIdentity = null,
       createdRoutine = null;

  const CreateRoutineStoreAcknowledgement.ownerExpired({required this.identity})
    : disposition = CreateRoutineStoreDisposition.ownerExpired,
      receiptIdentity = null,
      createdRoutine = null,
      errorMessage = null;

  CreateRoutineStoreAcknowledgement.effectUncertain({
    required this.identity,
    this.receiptIdentity,
    this.createdRoutine,
    this.errorMessage,
  }) : disposition = CreateRoutineStoreDisposition.effectUncertain {
    if ((receiptIdentity == null) != (createdRoutine == null)) {
      throw ArgumentError(
        'An uncertain routine write must include both receipt and routine.',
      );
    }
    if (receiptIdentity != null) _validateReceipt();
  }

  final CreateRoutineRuntimeIdentity identity;
  final CreateRoutineStoreDisposition disposition;
  final CreateRoutineReceiptIdentity? receiptIdentity;
  final Routine? createdRoutine;
  final String? errorMessage;

  String? get compensationToken => receiptIdentity?.compensationToken;

  void _validateReceipt() {
    if (receiptIdentity!.runtime != identity ||
        createRoutineDigest(createdRoutine!) !=
            receiptIdentity!.createdRoutineDigest) {
      throw ArgumentError('Routine store receipt identity mismatch.');
    }
  }
}

enum CreateRoutineSnapshotDisposition {
  captured,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class CreateRoutineSnapshotAcknowledgement {
  CreateRoutineSnapshotAcknowledgement.captured({
    required this.receiptIdentity,
    required List<Routine> routines,
  }) : disposition = CreateRoutineSnapshotDisposition.captured,
       routines = List<Routine>.unmodifiable(routines);

  CreateRoutineSnapshotAcknowledgement.rejected({required this.receiptIdentity})
    : disposition = CreateRoutineSnapshotDisposition.rejected,
      routines = null;

  CreateRoutineSnapshotAcknowledgement.ownerExpired({
    required this.receiptIdentity,
  }) : disposition = CreateRoutineSnapshotDisposition.ownerExpired,
       routines = null;

  CreateRoutineSnapshotAcknowledgement.effectUncertain({
    required this.receiptIdentity,
  }) : disposition = CreateRoutineSnapshotDisposition.effectUncertain,
       routines = null;

  final CreateRoutineReceiptIdentity receiptIdentity;
  final CreateRoutineSnapshotDisposition disposition;
  final List<Routine>? routines;

  CreateRoutineRuntimeIdentity get identity => receiptIdentity.runtime;
  String get compensationToken => receiptIdentity.compensationToken;
}

enum CreateRoutineCompensationDisposition {
  reverted,
  alreadyAbsent,
  rejected,
  ownerExpired,
  effectUncertain,
}

final class CreateRoutineCompensationAcknowledgement {
  CreateRoutineCompensationAcknowledgement({
    required this.receiptIdentity,
    required this.disposition,
    this.errorMessage,
  });

  final CreateRoutineReceiptIdentity receiptIdentity;
  final CreateRoutineCompensationDisposition disposition;
  final String? errorMessage;

  CreateRoutineRuntimeIdentity get identity => receiptIdentity.runtime;
  String get compensationToken => receiptIdentity.compensationToken;
}

final class CreateRoutineSuccessIdentity {
  CreateRoutineSuccessIdentity({required this.receiptIdentity});

  final CreateRoutineReceiptIdentity receiptIdentity;

  CreateRoutineRuntimeIdentity get runtime => receiptIdentity.runtime;
  String get compensationToken => receiptIdentity.compensationToken;

  @override
  bool operator ==(Object other) =>
      other is CreateRoutineSuccessIdentity &&
      other.receiptIdentity == receiptIdentity;

  @override
  int get hashCode => receiptIdentity.hashCode;
}

enum CreateRoutineSuccessDisposition {
  acknowledged,
  released,
  ownerExpired,
  effectUncertain,
}

final class CreateRoutineSuccessAcknowledgement {
  const CreateRoutineSuccessAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final CreateRoutineSuccessIdentity identity;
  final CreateRoutineSuccessDisposition disposition;
}

enum CreateRoutineSuccessReleaseDisposition { released, effectUncertain }

final class CreateRoutineSuccessReleaseAcknowledgement {
  const CreateRoutineSuccessReleaseAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final CreateRoutineSuccessIdentity identity;
  final CreateRoutineSuccessReleaseDisposition disposition;
}

enum CreateRoutineRuntimeDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
  boundaryMismatch,
}

/// Final classified completion returned to the notifier dispatch boundary.
final class CreateRoutineRuntimeCompletion {
  const CreateRoutineRuntimeCompletion({
    required this.identity,
    required this.disposition,
    required this.result,
  });

  final CreateRoutineRuntimeIdentity identity;
  final CreateRoutineRuntimeDisposition disposition;
  final McpToolResult result;
}

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  if (normalized != value) {
    throw ArgumentError.value(
      value,
      name,
      '$name must not contain leading or trailing whitespace.',
    );
  }
  return value;
}

String _canonicalToolName(String toolName) {
  if (toolName != createRoutineToolName) {
    throw ArgumentError.value(
      toolName,
      'toolName',
      'toolName must be exactly $createRoutineToolName.',
    );
  }
  return toolName;
}

String _argumentDigest(Map<String, dynamic> arguments) {
  final canonical = _canonicalJson(arguments);
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

String createRoutineRequestDigest(RoutineStoreCreateRequest request) =>
    _digestJson({
      'name': request.name,
      'prompt': request.prompt,
      'intervalValue': request.intervalValue,
      'intervalUnit': request.intervalUnit.name,
      'scheduleMode': request.scheduleMode.name,
      'timeOfDayMinutes': request.timeOfDayMinutes,
      'enabled': request.enabled,
      'notifyOnCompletion': request.notifyOnCompletion,
      'toolsEnabled': request.toolsEnabled,
      'completionAction': request.completionAction.name,
      'googleChatRule': request.googleChatRule.name,
      'workspaceDirectory': request.workspaceDirectory,
      'allowWorkspaceWrites': request.allowWorkspaceWrites,
    });

String createRoutineDigest(Routine routine) => _digestJson(routine.toJson());

String _digestJson(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonicalJson(value)))).toString();

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
