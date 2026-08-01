import 'dart:collection';

import 'routine_creation_receipt.dart';

/// Owns pending receipts and bounded exact terminal evidence.
final class RoutineCreationReceiptLedger {
  RoutineCreationReceiptLedger({
    required this.maxPendingReceipts,
    required this.maxTombstones,
  }) {
    if (maxPendingReceipts < 1) {
      throw ArgumentError.value(
        maxPendingReceipts,
        'maxPendingReceipts',
        'maxPendingReceipts must be positive.',
      );
    }
    if (maxTombstones < 1) {
      throw ArgumentError.value(
        maxTombstones,
        'maxTombstones',
        'maxTombstones must be positive.',
      );
    }
  }

  final int maxPendingReceipts;
  final int maxTombstones;
  final Map<String, RoutineCreationReceipt> _pending = {};
  final LinkedHashMap<String, RoutineCreationReceiptTombstone> _tombstones =
      LinkedHashMap<String, RoutineCreationReceiptTombstone>();

  int get pendingCount => _pending.length;
  int get tombstoneCount => _tombstones.length;

  RoutineCreationReceipt? pending(RoutineCreationReceiptClaim claim) {
    final receipt = _pending[claim.token];
    return receipt?.claim == claim ? receipt : null;
  }

  RoutineCreationReceiptTombstone? terminal(
    RoutineCreationReceiptClaim claim,
  ) {
    final tombstone = _tombstones[claim.token];
    return tombstone?.claim == claim ? tombstone : null;
  }

  RoutineCreationReceipt? pendingWithBinding(
    RoutineCreationReceiptBinding binding,
  ) {
    for (final receipt in _pending.values) {
      if (receipt.binding == binding) return receipt;
    }
    return null;
  }

  RoutineCreationReceiptTombstone? terminalWithBinding(
    RoutineCreationReceiptBinding binding,
  ) {
    for (final tombstone in _tombstones.values) {
      if (tombstone.receipt.binding == binding) return tombstone;
    }
    return null;
  }

  bool containsToken(String token) =>
      _pending.containsKey(token) || _tombstones.containsKey(token);

  void addPending(RoutineCreationReceipt receipt) {
    if (_pending.length >= maxPendingReceipts) {
      throw const RoutineCreationPreEffectRejection(
        'Too many routine creation receipts are awaiting settlement.',
      );
    }
    if (containsToken(receipt.token)) {
      throw const RoutineCreationPreEffectRejection(
        'A routine creation receipt token already exists.',
      );
    }
    if (pendingWithBinding(receipt.binding) != null ||
        terminalWithBinding(receipt.binding) != null) {
      throw const RoutineCreationPreEffectRejection(
        'A routine creation receipt already exists for this exact call.',
      );
    }
    _pending[receipt.token] = receipt;
  }

  void replacePending(RoutineCreationReceipt receipt) {
    if (!_pending.containsKey(receipt.token)) {
      throw StateError('Routine creation receipt is no longer pending.');
    }
    _pending[receipt.token] = receipt;
  }

  bool removePending(RoutineCreationReceiptClaim claim) {
    final receipt = pending(claim);
    return receipt != null && _pending.remove(claim.token) == receipt;
  }

  void rememberReleased(RoutineCreationReceipt receipt) {
    _rememberTerminal(
      RoutineCreationReceiptTombstone.released(receipt: receipt),
    );
  }

  void rememberCompensated(
    RoutineCreationReceipt receipt,
    RoutineCreationCompensationDisposition disposition,
  ) {
    _rememberTerminal(
      RoutineCreationReceiptTombstone.compensated(
        receipt: receipt,
        disposition: disposition,
      ),
    );
  }

  void _rememberTerminal(RoutineCreationReceiptTombstone tombstone) {
    _pending.remove(tombstone.receipt.token);
    _tombstones.remove(tombstone.receipt.token);
    _tombstones[tombstone.receipt.token] = tombstone;
    while (_tombstones.length > maxTombstones) {
      _tombstones.remove(_tombstones.keys.first);
    }
  }
}
