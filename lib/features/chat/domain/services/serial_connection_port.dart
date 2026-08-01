import '../entities/chat_turn_owner.dart';
import 'serial_connection_attempt_coordinator.dart';
import 'serial_connection_tool_contract.dart';

/// Opens and conditionally rolls back exact serial sessions.
abstract interface class SerialConnectionPort {
  /// Returns a stable non-empty session fingerprint whenever open succeeded.
  ///
  /// Return `failed` only after proving that no serial session was created.
  /// The handler treats every thrown exception as an uncertain side effect.
  Future<SerialConnectionResult> open(
    ChatTurnOwner owner,
    SerialConnectionRequest request,
  );

  /// Atomically closes only the session authorized by [permit].
  ///
  /// Implementations must compare the currently active session immediately
  /// before close and return `sessionMismatch` without closing on mismatch.
  Future<SerialConnectionRollbackResult> rollbackOpen(
    SerialConnectionRollbackPermit permit,
  );
}
