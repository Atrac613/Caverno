import '../entities/chat_turn_owner.dart';
import 'immutable_json_snapshot.dart';

part 'python_staging_lease_types.dart';

enum _RecordState {
  reserved,
  committed,
  releasedBeforeCommit,
  ownerClearedBeforeCommit,
  handlerCleanupClaimed,
  ownerCleanupClaimed,
  cleanupPending,
  settled,
}

final class _LeaseRecord {
  _LeaseRecord(this.attempt);

  final PythonStagingAttempt attempt;
  _RecordState state = _RecordState.reserved;
  PythonStagingLease? lease;
  PythonStagingCleanupClaim? activeClaim;
}

/// Pure owner-aware lifecycle registry for staged Python directories.
final class PythonStagingLeaseRegistry {
  PythonStagingLeaseRegistry({
    PythonStagingCleanupPendingCallback? onCleanupPending,
  }) : _onCleanupPending = onCleanupPending;

  final PythonStagingCleanupPendingCallback? _onCleanupPending;
  final Map<PythonStagingLeaseToken, _LeaseRecord> _records = {};
  final Map<PythonStagingAttempt, PythonStagingLeaseToken> _attemptTokens = {};
  final Map<String, PythonStagingLeaseToken> _pathClaims = {};
  final Map<_CleanupClaimToken, _LeaseRecord> _claimRecords = {};
  final Set<_CleanupClaimToken> _settledClaims = {};
  final Set<ChatTurnOwner> _ownerTombstones = {};
  final Set<PythonStagingAttempt> _pendingCleanupAttempts = {};

  List<PythonStagingAttempt> get pendingCleanupAttempts =>
      List.unmodifiable(_pendingCleanupAttempts);

  /// Returns staged directories that still require cleanup or settlement.
  ///
  /// Reserved attempts are intentionally excluded because no directory has
  /// been committed yet. A late allocation after owner retirement is handed
  /// back as a cleanup claim by [commit].
  List<PythonStagingAttempt> outstandingCleanupAttempts({
    ChatTurnOwner? owner,
  }) {
    final attempts = <PythonStagingAttempt>[];
    for (final record in _records.values) {
      if (owner != null && record.attempt.owner != owner) continue;
      if (switch (record.state) {
        _RecordState.committed ||
        _RecordState.handlerCleanupClaimed ||
        _RecordState.ownerCleanupClaimed ||
        _RecordState.cleanupPending => true,
        _ => false,
      }) {
        attempts.add(record.attempt);
      }
    }
    return List.unmodifiable(attempts);
  }

  PythonStagingReserveDisposition reserve(PythonStagingAttempt attempt) {
    if (_ownerTombstones.contains(attempt.owner)) {
      return const PythonStagingReserveDisposition._(
        PythonStagingReserveStatus.ownerCleared,
        null,
      );
    }
    if (_attemptTokens.containsKey(attempt)) {
      return const PythonStagingReserveDisposition._(
        PythonStagingReserveStatus.attemptConflict,
        null,
      );
    }
    final token = PythonStagingLeaseToken._();
    _records[token] = _LeaseRecord(attempt);
    _attemptTokens[attempt] = token;
    return PythonStagingReserveDisposition._(
      PythonStagingReserveStatus.reserved,
      token,
    );
  }

  PythonStagingCommitDisposition commit({
    required PythonStagingAttempt attempt,
    required PythonStagingLeaseToken token,
    required PythonStagingDirectoryIdentity directoryIdentity,
    Map<String, dynamic> metadata = const {},
  }) {
    final record = _records[token];
    if (record == null) return _commit(PythonStagingCommitStatus.unknownToken);
    if (record.attempt != attempt) {
      return _commit(PythonStagingCommitStatus.attemptMismatch);
    }
    if (record.state == _RecordState.reserved &&
        _ownerTombstones.contains(attempt.owner)) {
      record.state = _RecordState.ownerClearedBeforeCommit;
    }
    if (record.lease?.directoryIdentity == directoryIdentity) {
      return switch (record.state) {
        _RecordState.committed => PythonStagingCommitDisposition._(
          status: PythonStagingCommitStatus.alreadyCommitted,
          activeLease: record.lease,
        ),
        _RecordState.handlerCleanupClaimed ||
        _RecordState.ownerCleanupClaimed ||
        _RecordState.cleanupPending => _commit(
          PythonStagingCommitStatus.cleanupAlreadyClaimed,
        ),
        _ => _commit(PythonStagingCommitStatus.alreadySettled),
      };
    }
    switch (record.state) {
      case _RecordState.reserved:
        final lease = _newLease(record, token, directoryIdentity, metadata);
        if (lease == null) {
          return _commit(PythonStagingCommitStatus.pathConflict);
        }
        record
          ..lease = lease
          ..state = _RecordState.committed;
        return PythonStagingCommitDisposition._(
          status: PythonStagingCommitStatus.committed,
          activeLease: lease,
        );
      case _RecordState.releasedBeforeCommit:
      case _RecordState.ownerClearedBeforeCommit:
        final previousState = record.state;
        final lease = _newLease(record, token, directoryIdentity, metadata);
        if (lease == null) {
          return _commit(PythonStagingCommitStatus.pathConflict);
        }
        record.lease = lease;
        final claim = _claim(record, ownerCleanup: false);
        return PythonStagingCommitDisposition._(
          status: previousState == _RecordState.ownerClearedBeforeCommit
              ? PythonStagingCommitStatus.ownerCleared
              : PythonStagingCommitStatus.reservationReleased,
          cleanupClaim: claim,
        );
      case _RecordState.committed:
        return _commit(PythonStagingCommitStatus.duplicateStage);
      case _RecordState.handlerCleanupClaimed:
      case _RecordState.ownerCleanupClaimed:
      case _RecordState.cleanupPending:
      case _RecordState.settled:
        return _commit(PythonStagingCommitStatus.alreadySettled);
    }
  }

  bool isLeaseCurrent({
    required PythonStagingAttempt attempt,
    required PythonStagingLeaseToken token,
  }) {
    final record = _records[token];
    return record != null &&
        record.attempt == attempt &&
        record.state == _RecordState.committed &&
        !_ownerTombstones.contains(attempt.owner);
  }

  PythonStagingCleanupClaimDisposition claimCleanup({
    required PythonStagingAttempt attempt,
    required PythonStagingLeaseToken token,
  }) {
    final record = _records[token];
    if (record == null) {
      return _claimResult(PythonStagingCleanupClaimStatus.unknownToken);
    }
    if (record.attempt != attempt) {
      return _claimResult(PythonStagingCleanupClaimStatus.attemptMismatch);
    }
    return switch (record.state) {
      _RecordState.committed ||
      _RecordState.cleanupPending => PythonStagingCleanupClaimDisposition._(
        PythonStagingCleanupClaimStatus.claimed,
        _claim(record, ownerCleanup: false),
      ),
      _RecordState.handlerCleanupClaimed || _RecordState.ownerCleanupClaimed =>
        _claimResult(PythonStagingCleanupClaimStatus.alreadyClaimed),
      _RecordState.settled => _claimResult(
        PythonStagingCleanupClaimStatus.alreadySettled,
      ),
      _ => _claimResult(PythonStagingCleanupClaimStatus.noLease),
    };
  }

  PythonStagingCleanupSettleStatus settleCleanup({
    required PythonStagingCleanupClaim claim,
    required bool succeeded,
  }) {
    if (_settledClaims.contains(claim._token)) {
      return PythonStagingCleanupSettleStatus.alreadySettled;
    }
    final record = _claimRecords[claim._token];
    if (record == null ||
        !identical(record.activeClaim, claim) ||
        (record.state != _RecordState.handlerCleanupClaimed &&
            record.state != _RecordState.ownerCleanupClaimed)) {
      return PythonStagingCleanupSettleStatus.staleClaim;
    }
    record.activeClaim = null;
    _claimRecords.remove(claim._token);
    if (succeeded) {
      record.state = _RecordState.settled;
      _settledClaims.add(claim._token);
      return PythonStagingCleanupSettleStatus.settled;
    }
    record.state = _RecordState.cleanupPending;
    _pendingCleanupAttempts.add(record.attempt);
    _onCleanupPending?.call(record.attempt);
    return PythonStagingCleanupSettleStatus.reopened;
  }

  PythonStagingCleanupClaimDisposition claimPendingCleanup({
    ChatTurnOwner? owner,
  }) {
    for (final attempt in _pendingCleanupAttempts.toList()) {
      if (owner != null && attempt.owner != owner) continue;
      final token = _attemptTokens[attempt]!;
      return claimCleanup(attempt: attempt, token: token);
    }
    return _claimResult(PythonStagingCleanupClaimStatus.noLease);
  }

  PythonStagingReservationReleaseStatus releaseReservation({
    required PythonStagingAttempt attempt,
    required PythonStagingLeaseToken token,
  }) {
    final record = _records[token];
    if (record == null) {
      return PythonStagingReservationReleaseStatus.unknownToken;
    }
    if (record.attempt != attempt) {
      return PythonStagingReservationReleaseStatus.attemptMismatch;
    }
    return switch (record.state) {
      _RecordState.reserved => () {
        record.state = _RecordState.releasedBeforeCommit;
        return PythonStagingReservationReleaseStatus.cancelled;
      }(),
      _RecordState.releasedBeforeCommit ||
      _RecordState.ownerClearedBeforeCommit ||
      _RecordState.settled =>
        PythonStagingReservationReleaseStatus.alreadyReleased,
      _ => PythonStagingReservationReleaseStatus.leaseActive,
    };
  }

  PythonStagingClearDisposition clearOwner(ChatTurnOwner owner) {
    _ownerTombstones.add(owner);
    return _clear((record) => record.attempt.owner == owner);
  }

  PythonStagingClearDisposition clearAll() {
    _ownerTombstones.addAll(
      _records.values.map((record) => record.attempt.owner),
    );
    return _clear((_) => true);
  }

  PythonStagingClearDisposition _clear(bool Function(_LeaseRecord) select) {
    final claims = <PythonStagingCleanupClaim>[];
    var retiredReservations = 0;
    for (final record in _records.values.where(select)) {
      switch (record.state) {
        case _RecordState.reserved:
          record.state = _RecordState.ownerClearedBeforeCommit;
          retiredReservations += 1;
          continue;
        case _RecordState.committed:
        case _RecordState.cleanupPending:
          claims.add(_claim(record, ownerCleanup: true));
          continue;
        case _RecordState.releasedBeforeCommit:
          record.state = _RecordState.ownerClearedBeforeCommit;
          continue;
        case _RecordState.ownerClearedBeforeCommit:
        case _RecordState.handlerCleanupClaimed:
        case _RecordState.ownerCleanupClaimed:
        case _RecordState.settled:
          continue;
      }
    }
    return PythonStagingClearDisposition._(
      cleanupClaims: claims,
      retiredReservationCount: retiredReservations,
    );
  }

  PythonStagingLease? _newLease(
    _LeaseRecord record,
    PythonStagingLeaseToken token,
    PythonStagingDirectoryIdentity identity,
    Map<String, dynamic> metadata,
  ) {
    if (_pathClaims.containsKey(identity.claimKey)) return null;
    final lease = PythonStagingLease._(
      attempt: record.attempt,
      token: token,
      directoryIdentity: identity,
      metadata: metadata,
    );
    _pathClaims[identity.claimKey] = token;
    return lease;
  }

  PythonStagingCleanupClaim _claim(
    _LeaseRecord record, {
    required bool ownerCleanup,
  }) {
    final claim = PythonStagingCleanupClaim._(record.lease!);
    _pendingCleanupAttempts.remove(record.attempt);
    record
      ..activeClaim = claim
      ..state = ownerCleanup
          ? _RecordState.ownerCleanupClaimed
          : _RecordState.handlerCleanupClaimed;
    _claimRecords[claim._token] = record;
    return claim;
  }

  PythonStagingCommitDisposition _commit(PythonStagingCommitStatus status) =>
      PythonStagingCommitDisposition._(status: status);

  PythonStagingCleanupClaimDisposition _claimResult(
    PythonStagingCleanupClaimStatus status,
  ) => PythonStagingCleanupClaimDisposition._(status, null);
}
