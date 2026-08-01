import '../entities/chat_turn_owner.dart';

// ChatNotifier decomposition collaborator: ssh-session-ownership-coordinator

String _normalizedSshIdentityValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}

// dart format off
typedef SshConnectionOperationValue = ({ChatTurnOwner owner, String toolCallId, String toolName, String connectionDigest});
extension type SshConnectionOperationIdentity._(SshConnectionOperationValue _value) {
  SshConnectionOperationIdentity(SshConnectionOperationValue value)
    : this._((
        owner: value.owner,
        toolCallId: _normalizedSshIdentityValue(value.toolCallId, 'toolCallId'),
        toolName: _normalizedSshIdentityValue(value.toolName, 'toolName'),
        connectionDigest: _normalizedSshIdentityValue(value.connectionDigest, 'connectionDigest'),
      ));
  ChatTurnOwner get owner => _value.owner;
  String get toolCallId => _value.toolCallId;
  String get toolName => _value.toolName;
  String get connectionDigest => _value.connectionDigest;
}

typedef SshCommandOperationValue = ({ChatTurnOwner owner, String toolCallId, String toolName, String commandDigest});
extension type SshCommandOperationIdentity._(SshCommandOperationValue _value) {
  SshCommandOperationIdentity(SshCommandOperationValue value)
    : this._((
        owner: value.owner,
        toolCallId: _normalizedSshIdentityValue(value.toolCallId, 'toolCallId'),
        toolName: _normalizedSshIdentityValue(value.toolName, 'toolName'),
        commandDigest: _normalizedSshIdentityValue(value.commandDigest, 'commandDigest'),
      ));
  ChatTurnOwner get owner => _value.owner;
  String get toolCallId => _value.toolCallId;
  String get toolName => _value.toolName;
  String get commandDigest => _value.commandDigest;
}

extension type SshExternalSessionFingerprint._(String value) {
  SshExternalSessionFingerprint(String value)
    : this._(_normalizedSshIdentityValue(value, 'externalSessionFingerprint'));
}
// dart format on

extension type SshConnectToken._(Object _value) {}
extension type SshActivatedSessionToken._(Object _value) {}
extension type SshCommandLeaseToken._(Object _value) {}

typedef SshConnectAttempt = ({
  SshConnectionOperationIdentity identity,
  SshConnectToken token,
});

final class SshActivatedSession {
  const SshActivatedSession._(
    this.identity,
    this.token,
    this.externalFingerprint,
  );

  final SshConnectionOperationIdentity identity;
  final SshActivatedSessionToken token;
  final SshExternalSessionFingerprint externalFingerprint;
}

final class SshDisconnectReceipt {
  const SshDisconnectReceipt._(
    this.owner,
    this.connectionIdentity,
    this.connectToken,
    this.sessionToken,
    this.expectedFingerprint,
  );

  final ChatTurnOwner owner;
  final SshConnectionOperationIdentity connectionIdentity;
  final SshConnectToken? connectToken;
  final SshActivatedSessionToken? sessionToken;
  final SshExternalSessionFingerprint expectedFingerprint;
}

final class SshConditionalDisconnectPermit {
  const SshConditionalDisconnectPermit._(
    this.receipt,
    this.expectedFingerprint,
  );

  final SshDisconnectReceipt receipt;
  final SshExternalSessionFingerprint expectedFingerprint;
}

typedef SshCommandLease = ({
  SshCommandOperationIdentity operation,
  SshActivatedSessionToken sessionToken,
  SshCommandLeaseToken token,
});

// dart format off
enum SshOwnershipStatus {
  started, ownerRetired, registryCleared, identityMismatch,
  staleToken, foreignCapability, activated, fingerprintMismatch,
  alreadyCompleted, acquired, noActiveSession, staleSession,
  alreadyLeased, authorized, alreadyAuthorized, completed, retryRequired,
}

typedef SshConnectBeginResult = ({SshOwnershipStatus status, SshConnectAttempt? attempt});
typedef SshConnectCompletionResult = ({SshOwnershipStatus status, SshActivatedSession? session, SshDisconnectReceipt? cleanupReceipt});
typedef SshCommandLeaseAcquireResult = ({SshOwnershipStatus status, SshCommandLease? lease});
typedef SshSessionRetireResult = ({SshOwnershipStatus status, SshDisconnectReceipt? cleanupReceipt});
typedef SshDisconnectAuthorizationResult = ({SshOwnershipStatus status, SshConditionalDisconnectPermit? permit});
// dart format on

final class SshSessionClearResult {
  SshSessionClearResult(Iterable<SshDisconnectReceipt> cleanupReceipts)
    : cleanupReceipts = List.unmodifiable(cleanupReceipts);

  final List<SshDisconnectReceipt> cleanupReceipts;
}

enum _ConnectState { pending, superseded, finished, activated, rejected }

final class _ConnectRecord {
  _ConnectRecord(this.attempt);

  final SshConnectAttempt attempt;
  _ConnectState state = _ConnectState.pending;
  SshConnectCompletionResult? completion;
}

final class _SessionRecord {
  _SessionRecord(this.session);

  final SshActivatedSession session;
  bool retired = false;
  SshDisconnectReceipt? cleanupReceipt;
}

final class _CommandLeaseRecord {
  _CommandLeaseRecord(this.lease);

  final SshCommandLease lease;
  bool released = false;
}

final class _ReceiptRecord {
  bool completed = false;
  SshConditionalDisconnectPermit? activePermit;
}

final class SshSessionOwnershipCoordinator {
  final Map<SshConnectToken, _ConnectRecord> _connectRecords = {};
  final Map<ChatTurnOwner, SshConnectToken> _pendingByOwner = {};
  final Map<SshActivatedSessionToken, _SessionRecord> _sessionRecords = {};
  final Map<ChatTurnOwner, _SessionRecord> _activeByOwner = {};
  final Map<SshCommandLeaseToken, _CommandLeaseRecord> _commandRecords = {};
  final Map<SshCommandOperationIdentity, SshCommandLeaseToken>
  _commandByOperation = {};
  final Map<SshDisconnectReceipt, _ReceiptRecord> _receiptRecords = {};
  final Map<SshConditionalDisconnectPermit, _ReceiptRecord> _permitRecords = {};
  final Set<ChatTurnOwner> _retiredOwners = {};
  bool _registryCleared = false;

  SshActivatedSession? activeSession(ChatTurnOwner owner) =>
      _activeByOwner[owner]?.session;

  SshConnectBeginResult beginConnect(SshConnectionOperationIdentity identity) {
    if (_registryCleared) {
      return (status: SshOwnershipStatus.registryCleared, attempt: null);
    }
    if (_retiredOwners.contains(identity.owner)) {
      return (status: SshOwnershipStatus.ownerRetired, attempt: null);
    }
    final priorToken = _pendingByOwner[identity.owner];
    if (priorToken != null) {
      _connectRecords[priorToken]!.state = _ConnectState.superseded;
    }
    final attempt = (identity: identity, token: SshConnectToken._(Object()));
    _connectRecords[attempt.token] = _ConnectRecord(attempt);
    _pendingByOwner[identity.owner] = attempt.token;
    return (status: SshOwnershipStatus.started, attempt: attempt);
  }

  SshOwnershipStatus finishConnect(
    SshConnectionOperationIdentity identity,
    SshConnectToken token,
  ) {
    final record = _connectRecords[token];
    if (record == null) return SshOwnershipStatus.foreignCapability;
    if (record.attempt.identity != identity) {
      return SshOwnershipStatus.identityMismatch;
    }
    if (record.state == _ConnectState.finished) {
      return SshOwnershipStatus.alreadyCompleted;
    }
    if (record.state != _ConnectState.pending ||
        !identical(_pendingByOwner[identity.owner], token)) {
      return SshOwnershipStatus.staleToken;
    }
    _pendingByOwner.remove(identity.owner);
    record.state = _ConnectState.finished;
    return SshOwnershipStatus.completed;
  }

  SshConnectCompletionResult completeConnect({
    required SshConnectionOperationIdentity identity,
    required SshConnectToken token,
    required SshExternalSessionFingerprint externalFingerprint,
  }) {
    final record = _connectRecords[token];
    if (record == null) {
      return _completion(SshOwnershipStatus.foreignCapability);
    }
    if (record.attempt.identity != identity) {
      return _completion(SshOwnershipStatus.identityMismatch);
    }
    final priorCompletion = record.completion;
    if (priorCompletion != null) {
      return (
        status: SshOwnershipStatus.alreadyCompleted,
        session: priorCompletion.session,
        cleanupReceipt: priorCompletion.cleanupReceipt,
      );
    }

    final rejection = _completionRejection(record, token);
    if (rejection != null) {
      if (identical(_pendingByOwner[identity.owner], token)) {
        _pendingByOwner.remove(identity.owner);
      }
      record.state = _ConnectState.rejected;
      final receipt = _newReceipt(identity, token, null, externalFingerprint);
      final result = _completion(rejection, cleanupReceipt: receipt);
      record.completion = result;
      return result;
    }

    _pendingByOwner.remove(identity.owner);
    record.state = _ConnectState.activated;
    final session = SshActivatedSession._(
      identity,
      SshActivatedSessionToken._(Object()),
      externalFingerprint,
    );
    final sessionRecord = _SessionRecord(session);
    final prior = _activeByOwner[identity.owner];
    final cleanupReceipt = prior == null ? null : _retireRecord(prior);
    _activeByOwner[identity.owner] = sessionRecord;
    _sessionRecords[session.token] = sessionRecord;
    final result = _completion(
      SshOwnershipStatus.activated,
      session: session,
      cleanupReceipt: cleanupReceipt,
    );
    record.completion = result;
    return result;
  }

  SshCommandLeaseAcquireResult acquireCommandLease({
    required SshCommandOperationIdentity operation,
    required SshActivatedSessionToken sessionToken,
  }) {
    if (_registryCleared) {
      return _commandAcquisition(SshOwnershipStatus.registryCleared);
    }
    if (_retiredOwners.contains(operation.owner)) {
      return _commandAcquisition(SshOwnershipStatus.ownerRetired);
    }
    final suppliedSession = _sessionRecords[sessionToken];
    if (suppliedSession == null) {
      return _commandAcquisition(SshOwnershipStatus.foreignCapability);
    }
    final active = _activeByOwner[operation.owner];
    if (active == null) {
      return _commandAcquisition(SshOwnershipStatus.noActiveSession);
    }
    if (!identical(active, suppliedSession)) {
      return _commandAcquisition(SshOwnershipStatus.staleSession);
    }
    final priorToken = _commandByOperation[operation];
    if (priorToken != null &&
        isCommandLeaseCurrent(operation, sessionToken, priorToken)) {
      return _commandAcquisition(SshOwnershipStatus.alreadyLeased);
    }
    final lease = (
      operation: operation,
      sessionToken: sessionToken,
      token: SshCommandLeaseToken._(Object()),
    );
    _commandRecords[lease.token] = _CommandLeaseRecord(lease);
    _commandByOperation[operation] = lease.token;
    return _commandAcquisition(SshOwnershipStatus.acquired, lease);
  }

  bool isCommandLeaseCurrent(
    SshCommandOperationIdentity operation,
    SshActivatedSessionToken sessionToken,
    SshCommandLeaseToken leaseToken,
  ) {
    final record = _commandRecords[leaseToken];
    return record != null &&
        !record.released &&
        record.lease.operation == operation &&
        identical(record.lease.sessionToken, sessionToken) &&
        identical(_commandByOperation[operation], leaseToken) &&
        identical(_activeByOwner[operation.owner]?.session.token, sessionToken);
  }

  SshOwnershipStatus releaseCommandLease({
    required SshCommandOperationIdentity operation,
    required SshActivatedSessionToken sessionToken,
    required SshCommandLeaseToken leaseToken,
  }) {
    final record = _commandRecords[leaseToken];
    if (record == null) return SshOwnershipStatus.foreignCapability;
    if (record.lease.operation != operation ||
        !identical(record.lease.sessionToken, sessionToken)) {
      return SshOwnershipStatus.identityMismatch;
    }
    if (record.released) {
      return SshOwnershipStatus.alreadyCompleted;
    }
    final wasCurrent = isCommandLeaseCurrent(
      operation,
      sessionToken,
      leaseToken,
    );
    record.released = true;
    if (identical(_commandByOperation[operation], leaseToken)) {
      _commandByOperation.remove(operation);
    }
    return wasCurrent
        ? SshOwnershipStatus.completed
        : SshOwnershipStatus.staleSession;
  }

  SshSessionRetireResult retireSession(
    ChatTurnOwner owner,
    SshActivatedSessionToken token,
  ) {
    final record = _sessionRecords[token];
    if (record == null) {
      return _retirement(SshOwnershipStatus.foreignCapability);
    }
    if (record.session.identity.owner != owner) {
      return _retirement(SshOwnershipStatus.identityMismatch);
    }
    if (record.retired) {
      return _retirement(
        SshOwnershipStatus.alreadyCompleted,
        record.cleanupReceipt,
      );
    }
    if (!identical(_activeByOwner[owner], record)) {
      return _retirement(SshOwnershipStatus.staleToken);
    }
    _activeByOwner.remove(owner);
    return _retirement(SshOwnershipStatus.completed, _retireRecord(record));
  }

  SshDisconnectAuthorizationResult authorizeDisconnect({
    required SshDisconnectReceipt receipt,
    required SshExternalSessionFingerprint observedFingerprint,
  }) {
    final record = _receiptRecords[receipt];
    if (record == null) {
      return _authorization(SshOwnershipStatus.foreignCapability);
    }
    if (record.completed) {
      return _authorization(SshOwnershipStatus.alreadyCompleted);
    }
    if (receipt.expectedFingerprint != observedFingerprint) {
      return _authorization(SshOwnershipStatus.fingerprintMismatch);
    }
    final existing = record.activePermit;
    if (existing != null) {
      return _authorization(SshOwnershipStatus.alreadyAuthorized, existing);
    }
    final permit = SshConditionalDisconnectPermit._(
      receipt,
      observedFingerprint,
    );
    record.activePermit = permit;
    _permitRecords[permit] = record;
    return _authorization(SshOwnershipStatus.authorized, permit);
  }

  SshOwnershipStatus finishDisconnect(
    SshConditionalDisconnectPermit permit, {
    required bool succeeded,
  }) {
    final record = _permitRecords[permit];
    if (record == null) return SshOwnershipStatus.foreignCapability;
    if (record.completed) {
      return SshOwnershipStatus.alreadyCompleted;
    }
    if (!identical(record.activePermit, permit)) {
      return SshOwnershipStatus.staleToken;
    }
    record.activePermit = null;
    if (!succeeded) return SshOwnershipStatus.retryRequired;
    record.completed = true;
    return SshOwnershipStatus.completed;
  }

  SshSessionClearResult clearOwner(ChatTurnOwner owner) {
    _retiredOwners.add(owner);
    _pendingByOwner.remove(owner);
    final active = _activeByOwner.remove(owner);
    return SshSessionClearResult(
      active == null ? const [] : [_retireRecord(active)],
    );
  }

  SshSessionClearResult clearAll() {
    if (_registryCleared) return SshSessionClearResult(const []);
    _registryCleared = true;
    _retiredOwners.addAll(_pendingByOwner.keys);
    _retiredOwners.addAll(_activeByOwner.keys);
    _pendingByOwner.clear();
    final receipts = _activeByOwner.values.map(_retireRecord).toList();
    _activeByOwner.clear();
    return SshSessionClearResult(receipts);
  }

  SshOwnershipStatus? _completionRejection(
    _ConnectRecord record,
    SshConnectToken token,
  ) {
    final owner = record.attempt.identity.owner;
    if (_registryCleared) return SshOwnershipStatus.registryCleared;
    if (_retiredOwners.contains(owner)) {
      return SshOwnershipStatus.ownerRetired;
    }
    if (record.state != _ConnectState.pending ||
        !identical(_pendingByOwner[owner], token)) {
      return SshOwnershipStatus.staleToken;
    }
    return null;
  }

  SshDisconnectReceipt _retireRecord(_SessionRecord record) {
    record.retired = true;
    return record.cleanupReceipt ??= _newReceipt(
      record.session.identity,
      null,
      record.session.token,
      record.session.externalFingerprint,
    );
  }

  SshDisconnectReceipt _newReceipt(
    SshConnectionOperationIdentity identity,
    SshConnectToken? connectToken,
    SshActivatedSessionToken? sessionToken,
    SshExternalSessionFingerprint fingerprint,
  ) {
    final receipt = SshDisconnectReceipt._(
      identity.owner,
      identity,
      connectToken,
      sessionToken,
      fingerprint,
    );
    _receiptRecords[receipt] = _ReceiptRecord();
    return receipt;
  }
}

SshConnectCompletionResult _completion(
  SshOwnershipStatus status, {
  SshActivatedSession? session,
  SshDisconnectReceipt? cleanupReceipt,
}) => (status: status, session: session, cleanupReceipt: cleanupReceipt);

SshCommandLeaseAcquireResult _commandAcquisition(
  SshOwnershipStatus status, [
  SshCommandLease? lease,
]) => (status: status, lease: lease);

SshSessionRetireResult _retirement(
  SshOwnershipStatus status, [
  SshDisconnectReceipt? cleanupReceipt,
]) => (status: status, cleanupReceipt: cleanupReceipt);

SshDisconnectAuthorizationResult _authorization(
  SshOwnershipStatus status, [
  SshConditionalDisconnectPermit? permit,
]) => (status: status, permit: permit);
