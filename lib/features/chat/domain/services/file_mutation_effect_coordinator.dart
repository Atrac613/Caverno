import '../entities/chat_turn_owner.dart';

String _requiredEvidence(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}

/// Exact identity for one filesystem mutation attempt.
final class FileMutationOperationIdentity {
  FileMutationOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String canonicalPath,
  }) : toolCallId = toolCallId.trim(),
       toolName = toolName.trim(),
       canonicalPath = canonicalPath.trim() {
    if (this.toolCallId.isEmpty) {
      throw ArgumentError.value(toolCallId, 'toolCallId', 'Must not be empty.');
    }
    if (this.toolName.isEmpty) {
      throw ArgumentError.value(toolName, 'toolName', 'Must not be empty.');
    }
    if (this.canonicalPath.isEmpty) {
      throw ArgumentError.value(
        canonicalPath,
        'canonicalPath',
        'Must not be empty.',
      );
    }
  }

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String canonicalPath;

  bool matches(FileMutationOperationIdentity other) {
    return owner == other.owner &&
        toolCallId == other.toolCallId &&
        toolName == other.toolName &&
        canonicalPath == other.canonicalPath;
  }
}

/// Opaque path lease held until the effect is committed or compensated.
final class FileMutationEffectLease {
  const FileMutationEffectLease._({
    required this.identity,
    required this.beforeFingerprint,
    required int token,
  }) : _token = token;

  final FileMutationOperationIdentity identity;
  final String beforeFingerprint;
  final int _token;

  bool belongsTo(FileMutationOperationIdentity expected) {
    return identity.matches(expected);
  }
}

/// Receipt proving which exact applied effect requires compensation.
final class FileMutationAppliedReceipt {
  const FileMutationAppliedReceipt._({
    required this.lease,
    required this.expectedAfterFingerprint,
    required this.compensationToken,
  });

  final FileMutationEffectLease lease;
  final String expectedAfterFingerprint;
  final String compensationToken;

  bool belongsTo(FileMutationOperationIdentity expected) {
    return lease.belongsTo(expected);
  }
}

enum FileMutationAcquireDisposition { acquired, ownerRetired, pathBusy }

final class FileMutationAcquireResult {
  const FileMutationAcquireResult._(this.disposition, this.lease);

  const FileMutationAcquireResult.acquired(FileMutationEffectLease lease)
    : this._(FileMutationAcquireDisposition.acquired, lease);

  const FileMutationAcquireResult.ownerRetired()
    : this._(FileMutationAcquireDisposition.ownerRetired, null);

  const FileMutationAcquireResult.pathBusy()
    : this._(FileMutationAcquireDisposition.pathBusy, null);

  final FileMutationAcquireDisposition disposition;
  final FileMutationEffectLease? lease;
}

enum FileMutationApplyDisposition {
  applied,
  compensationRequired,
  invalidLease,
}

final class FileMutationApplyResult {
  const FileMutationApplyResult._(this.disposition, this.receipt);

  const FileMutationApplyResult.applied(FileMutationAppliedReceipt receipt)
    : this._(FileMutationApplyDisposition.applied, receipt);

  const FileMutationApplyResult.compensationRequired(
    FileMutationAppliedReceipt receipt,
  ) : this._(FileMutationApplyDisposition.compensationRequired, receipt);

  const FileMutationApplyResult.invalidLease()
    : this._(FileMutationApplyDisposition.invalidLease, null);

  final FileMutationApplyDisposition disposition;
  final FileMutationAppliedReceipt? receipt;
}

enum FileMutationCommitDisposition {
  committed,
  compensationRequired,
  invalidReceipt,
}

enum FileMutationCompensationDisposition {
  ready,
  fingerprintConflict,
  invalidReceipt,
  reverted,
  failed,
}

/// Work retained when an owner retires during or after a filesystem effect.
final class FileMutationOwnerRetirement {
  FileMutationOwnerRetirement({
    required List<FileMutationAppliedReceipt> compensationRequired,
    required List<FileMutationEffectLease> effectsInFlight,
  }) : compensationRequired = List.unmodifiable(compensationRequired),
       effectsInFlight = List.unmodifiable(effectsInFlight);

  final List<FileMutationAppliedReceipt> compensationRequired;
  final List<FileMutationEffectLease> effectsInFlight;
}

enum _EffectPhase { reserved, executing, applied, compensating }

final class _EffectEntry {
  _EffectEntry(this.lease);

  final FileMutationEffectLease lease;
  _EffectPhase phase = _EffectPhase.reserved;
  FileMutationAppliedReceipt? receipt;
}

/// Fences path effects until an exact owner attempt commits or compensates.
final class FileMutationEffectCoordinator {
  final Map<int, _EffectEntry> _entriesByToken = {};
  final Map<String, int> _tokenByPath = {};
  final Set<ChatTurnOwner> _retiredOwners = {};
  var _nextToken = 1;
  var _cleared = false;

  FileMutationAcquireResult acquire(
    FileMutationOperationIdentity identity, {
    required String beforeFingerprint,
  }) {
    if (_cleared || _retiredOwners.contains(identity.owner)) {
      return const FileMutationAcquireResult.ownerRetired();
    }
    if (_tokenByPath.containsKey(identity.canonicalPath)) {
      return const FileMutationAcquireResult.pathBusy();
    }
    final lease = FileMutationEffectLease._(
      identity: identity,
      beforeFingerprint: _requiredEvidence(
        beforeFingerprint,
        'beforeFingerprint',
      ),
      token: _nextToken++,
    );
    _entriesByToken[lease._token] = _EffectEntry(lease);
    _tokenByPath[identity.canonicalPath] = lease._token;
    return FileMutationAcquireResult.acquired(lease);
  }

  /// Must be called immediately before the underlying mutation starts.
  bool beginEffect(
    FileMutationOperationIdentity identity,
    FileMutationEffectLease lease,
  ) {
    final entry = _entry(identity, lease);
    if (entry == null || entry.phase != _EffectPhase.reserved) {
      return false;
    }
    if (_cleared || _retiredOwners.contains(identity.owner)) {
      _remove(entry);
      return false;
    }
    entry.phase = _EffectPhase.executing;
    return true;
  }

  FileMutationApplyResult markApplied(
    FileMutationOperationIdentity identity,
    FileMutationEffectLease lease, {
    required String expectedAfterFingerprint,
    required String compensationToken,
  }) {
    final entry = _entry(identity, lease);
    if (entry == null || entry.phase != _EffectPhase.executing) {
      return const FileMutationApplyResult.invalidLease();
    }
    final afterFingerprint = _requiredEvidence(
      expectedAfterFingerprint,
      'expectedAfterFingerprint',
    );
    final normalizedCompensationToken = _requiredEvidence(
      compensationToken,
      'compensationToken',
    );
    final receipt = FileMutationAppliedReceipt._(
      lease: lease,
      expectedAfterFingerprint: afterFingerprint,
      compensationToken: normalizedCompensationToken,
    );
    entry
      ..phase = _EffectPhase.applied
      ..receipt = receipt;
    return _cleared || _retiredOwners.contains(identity.owner)
        ? FileMutationApplyResult.compensationRequired(receipt)
        : FileMutationApplyResult.applied(receipt);
  }

  /// Releases an attempt proven to have produced no filesystem effect.
  bool finishWithoutEffect(
    FileMutationOperationIdentity identity,
    FileMutationEffectLease lease,
  ) {
    final entry = _entry(identity, lease);
    if (entry == null ||
        (entry.phase != _EffectPhase.reserved &&
            entry.phase != _EffectPhase.executing)) {
      return false;
    }
    _remove(entry);
    return true;
  }

  FileMutationCommitDisposition finishCommitted(
    FileMutationOperationIdentity identity,
    FileMutationAppliedReceipt receipt,
  ) {
    final entry = _receiptEntry(identity, receipt);
    if (entry == null || entry.phase != _EffectPhase.applied) {
      return FileMutationCommitDisposition.invalidReceipt;
    }
    if (_cleared || _retiredOwners.contains(identity.owner)) {
      return FileMutationCommitDisposition.compensationRequired;
    }
    _remove(entry);
    return FileMutationCommitDisposition.committed;
  }

  FileMutationCompensationDisposition beginCompensation(
    FileMutationOperationIdentity identity,
    FileMutationAppliedReceipt receipt, {
    required String observedCurrentFingerprint,
  }) {
    final entry = _receiptEntry(identity, receipt);
    if (entry == null || entry.phase != _EffectPhase.applied) {
      return FileMutationCompensationDisposition.invalidReceipt;
    }
    final observedFingerprint = _requiredEvidence(
      observedCurrentFingerprint,
      'observedCurrentFingerprint',
    );
    if (observedFingerprint != receipt.expectedAfterFingerprint) {
      return FileMutationCompensationDisposition.fingerprintConflict;
    }
    entry.phase = _EffectPhase.compensating;
    return FileMutationCompensationDisposition.ready;
  }

  FileMutationCompensationDisposition completeCompensation(
    FileMutationOperationIdentity identity,
    FileMutationAppliedReceipt receipt, {
    required bool succeeded,
  }) {
    final entry = _receiptEntry(identity, receipt);
    if (entry == null || entry.phase != _EffectPhase.compensating) {
      return FileMutationCompensationDisposition.invalidReceipt;
    }
    if (!succeeded) {
      entry.phase = _EffectPhase.applied;
      return FileMutationCompensationDisposition.failed;
    }
    _remove(entry);
    return FileMutationCompensationDisposition.reverted;
  }

  FileMutationOwnerRetirement retireOwner(ChatTurnOwner owner) {
    _retiredOwners.add(owner);
    return _retireMatching((entry) => entry.lease.identity.owner == owner);
  }

  FileMutationOwnerRetirement clearAll() {
    _cleared = true;
    _retiredOwners.addAll(
      _entriesByToken.values.map((entry) => entry.lease.identity.owner),
    );
    return _retireMatching((_) => true);
  }

  bool isPathBusy(String canonicalPath) {
    return _tokenByPath.containsKey(canonicalPath.trim());
  }

  _EffectEntry? _entry(
    FileMutationOperationIdentity identity,
    FileMutationEffectLease lease,
  ) {
    if (!lease.belongsTo(identity)) return null;
    final entry = _entriesByToken[lease._token];
    return identical(entry?.lease, lease) ? entry : null;
  }

  _EffectEntry? _receiptEntry(
    FileMutationOperationIdentity identity,
    FileMutationAppliedReceipt receipt,
  ) {
    if (!receipt.belongsTo(identity)) return null;
    final entry = _entriesByToken[receipt.lease._token];
    return identical(entry?.receipt, receipt) ? entry : null;
  }

  FileMutationOwnerRetirement _retireMatching(
    bool Function(_EffectEntry entry) predicate,
  ) {
    final compensationRequired = <FileMutationAppliedReceipt>[];
    final effectsInFlight = <FileMutationEffectLease>[];
    for (final entry in _entriesByToken.values.toList(growable: false)) {
      if (!predicate(entry)) continue;
      switch (entry.phase) {
        case _EffectPhase.reserved:
          _remove(entry);
        case _EffectPhase.executing:
          effectsInFlight.add(entry.lease);
        case _EffectPhase.applied:
        case _EffectPhase.compensating:
          compensationRequired.add(entry.receipt!);
      }
    }
    return FileMutationOwnerRetirement(
      compensationRequired: compensationRequired,
      effectsInFlight: effectsInFlight,
    );
  }

  void _remove(_EffectEntry entry) {
    _entriesByToken.remove(entry.lease._token);
    if (_tokenByPath[entry.lease.identity.canonicalPath] ==
        entry.lease._token) {
      _tokenByPath.remove(entry.lease.identity.canonicalPath);
    }
  }
}
