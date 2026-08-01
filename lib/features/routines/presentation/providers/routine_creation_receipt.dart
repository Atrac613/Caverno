import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/routine.dart';

enum RoutineCreationCommitDisposition {
  committed,
  rejectedBeforeEffect,
  ownerExpiredBeforeEffect,
  effectUncertain,
}

enum RoutineCreationCompensationDisposition {
  reverted,
  alreadyAbsent,
  conflict,
  unknownToken,
  effectUncertain,
}

enum RoutineCreationReceiptPhase {
  prepared,
  committed,
  settlementPrepared,
  effectUncertain,
}

enum RoutineCreationSettlementDisposition {
  prepared,
  released,
  ownerExpired,
  conflict,
  unknownToken,
  effectUncertain,
}

enum RoutineCreationTerminalDisposition { released, compensated }

typedef RoutineCreationPreEffectGuard =
    bool Function(RoutineCreationReceiptBinding binding);

final class RoutineCreationPreEffectRejection implements Exception {
  const RoutineCreationPreEffectRejection(this.message);

  final String message;

  @override
  String toString() => message;
}

final class RoutineCreationAttempt {
  const RoutineCreationAttempt({
    required this.receipt,
    required this.disposition,
    this.error,
  });

  final RoutineCreationReceipt receipt;
  final RoutineCreationCommitDisposition disposition;
  final Object? error;
}

/// Exact runtime binding for one routine creation side effect.
final class RoutineCreationReceiptBinding {
  RoutineCreationReceiptBinding({
    required String conversationId,
    required this.interactionGeneration,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
    required String requestDigest,
  }) : conversationId = _required(conversationId, 'conversationId'),
       toolCallId = _required(toolCallId, 'toolCallId'),
       toolName = _required(toolName, 'toolName'),
       argumentDigest = _required(argumentDigest, 'argumentDigest'),
       requestDigest = _required(requestDigest, 'requestDigest') {
    if (interactionGeneration < 1) {
      throw ArgumentError.value(
        interactionGeneration,
        'interactionGeneration',
        'interactionGeneration must be positive.',
      );
    }
  }

  final String conversationId;
  final int interactionGeneration;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;
  final String requestDigest;

  @override
  bool operator ==(Object other) =>
      other is RoutineCreationReceiptBinding &&
      other.conversationId == conversationId &&
      other.interactionGeneration == interactionGeneration &&
      other.toolCallId == toolCallId &&
      other.toolName == toolName &&
      other.argumentDigest == argumentDigest &&
      other.requestDigest == requestDigest;

  @override
  int get hashCode => Object.hash(
    conversationId,
    interactionGeneration,
    toolCallId,
    toolName,
    argumentDigest,
    requestDigest,
  );
}

/// Exact immutable claim required to inspect, settle, or compensate a receipt.
final class RoutineCreationReceiptClaim {
  RoutineCreationReceiptClaim({
    required String token,
    required this.binding,
    required String routineDigest,
  }) : token = _required(token, 'token'),
       routineDigest = _required(routineDigest, 'routineDigest');

  final String token;
  final RoutineCreationReceiptBinding binding;
  final String routineDigest;

  @override
  bool operator ==(Object other) =>
      other is RoutineCreationReceiptClaim &&
      other.token == token &&
      other.binding == binding &&
      other.routineDigest == routineDigest;

  @override
  int get hashCode => Object.hash(token, binding, routineDigest);
}

/// Preallocated identity for one compensable routine creation.
final class RoutineCreationReceipt {
  RoutineCreationReceipt({
    required String token,
    required this.binding,
    required this.routine,
    required String routineDigest,
    required this.phase,
  }) : token = _required(token, 'token'),
       routineDigest = _required(routineDigest, 'routineDigest') {
    if (this.routineDigest != routineCreationDigest(routine)) {
      throw ArgumentError.value(
        routineDigest,
        'routineDigest',
        'routineDigest must match the exact routine.',
      );
    }
  }

  final String token;
  final RoutineCreationReceiptBinding binding;
  final Routine routine;
  final String routineDigest;
  final RoutineCreationReceiptPhase phase;

  RoutineCreationReceiptClaim get claim => RoutineCreationReceiptClaim(
    token: token,
    binding: binding,
    routineDigest: routineDigest,
  );

  RoutineCreationReceipt withPhase(RoutineCreationReceiptPhase nextPhase) =>
      RoutineCreationReceipt(
        token: token,
        binding: binding,
        routine: routine,
        routineDigest: routineDigest,
        phase: nextPhase,
      );
}

/// Bounded terminal evidence retained after a receipt leaves the pending set.
final class RoutineCreationReceiptTombstone {
  const RoutineCreationReceiptTombstone.released({required this.receipt})
    : disposition = RoutineCreationTerminalDisposition.released,
      compensationDisposition = null;

  const RoutineCreationReceiptTombstone.compensated({
    required this.receipt,
    required RoutineCreationCompensationDisposition disposition,
  }) : disposition = RoutineCreationTerminalDisposition.compensated,
       compensationDisposition = disposition;

  final RoutineCreationReceipt receipt;
  final RoutineCreationTerminalDisposition disposition;
  final RoutineCreationCompensationDisposition? compensationDisposition;

  RoutineCreationReceiptClaim get claim => receipt.claim;
}

String routineCreationDigest(Routine routine) {
  final canonical = _canonicalJson(routine.toJson());
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}

String _required(String value, String name) {
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
