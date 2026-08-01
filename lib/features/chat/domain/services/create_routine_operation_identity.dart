import '../../../routines/domain/entities/routine.dart';
import '../entities/chat_turn_owner.dart';
import 'immutable_json_snapshot.dart';

const String createRoutineToolName = 'create_routine';

/// Immutable identity for one exact routine-creation tool call.
final class CreateRoutineOperationIdentity {
  CreateRoutineOperationIdentity({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
  }) {
    _requireExactNonEmpty(toolCallId, 'toolCallId');
    if (toolName != createRoutineToolName) {
      throw ArgumentError.value(
        toolName,
        'toolName',
        'toolName must be exactly $createRoutineToolName.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;

  bool belongsTo(CreateRoutineOperationIdentity expected) {
    return owner == expected.owner &&
        toolCallId == expected.toolCallId &&
        toolName == expected.toolName;
  }
}

enum RoutineStoreWriteDisposition { committed, rejected, ownerExpired }

final class RoutineStoreCompensationToken {
  RoutineStoreCompensationToken({required this.identity, required this.value}) {
    _requireExactNonEmpty(value, 'value');
  }

  final CreateRoutineOperationIdentity identity;
  final String value;

  bool belongsTo(CreateRoutineOperationIdentity expected) {
    return identity.belongsTo(expected);
  }
}

final class RoutineStoreWriteResult {
  const RoutineStoreWriteResult.committed({
    required this.identity,
    required this.compensationToken,
    required this.snapshot,
  }) : disposition = RoutineStoreWriteDisposition.committed,
       errorMessage = null;

  const RoutineStoreWriteResult.rejected({
    required this.identity,
    required this.errorMessage,
  }) : disposition = RoutineStoreWriteDisposition.rejected,
       compensationToken = null,
       snapshot = null;

  const RoutineStoreWriteResult.ownerExpired({required this.identity})
    : disposition = RoutineStoreWriteDisposition.ownerExpired,
      compensationToken = null,
      snapshot = null,
      errorMessage = null;

  final CreateRoutineOperationIdentity identity;
  final RoutineStoreWriteDisposition disposition;
  final RoutineStoreCompensationToken? compensationToken;
  final RoutineStoreSnapshot? snapshot;
  final String? errorMessage;

  ChatTurnOwner get owner => identity.owner;
  bool get didCommit => disposition == RoutineStoreWriteDisposition.committed;
}

enum RoutineStoreCompensationDisposition { reverted, alreadyAbsent, failed }

final class RoutineStoreCompensationResult {
  const RoutineStoreCompensationResult({
    required this.identity,
    required this.disposition,
    this.errorMessage,
  });

  final CreateRoutineOperationIdentity identity;
  final RoutineStoreCompensationDisposition disposition;
  final String? errorMessage;

  ChatTurnOwner get owner => identity.owner;
}

final class RoutineStoreSnapshot {
  RoutineStoreSnapshot({
    required this.identity,
    required List<Routine> routines,
    required this.createdRoutine,
  }) : routines = List<Routine>.unmodifiable(routines);

  final CreateRoutineOperationIdentity identity;
  final List<Routine> routines;
  final Routine createdRoutine;

  ChatTurnOwner get owner => identity.owner;
}

Map<String, dynamic> freezeCreateRoutineArguments(Map<String, dynamic> source) {
  return ImmutableJsonSnapshot.freezeMap(source);
}

void _requireExactNonEmpty(String value, String name) {
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
}
