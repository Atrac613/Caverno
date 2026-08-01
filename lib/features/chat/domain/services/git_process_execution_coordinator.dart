import '../entities/chat_turn_owner.dart';
import 'git_process_execution_contract.dart';
import 'immutable_json_snapshot.dart';

export 'git_process_execution_contract.dart';

part 'git_process_execution_receipts.dart';

// ChatNotifier decomposition collaborator: git-process-execution-coordinator
final class GitProcessAttemptToken {
  GitProcessAttemptToken._();
  @override
  String toString() => 'GitProcessAttemptToken(<opaque>)';
}

typedef GitProcessReserveResult = ({
  GitProcessReserveDisposition disposition,
  GitProcessAttemptToken? token,
});

final class GitProcessCancellationRequest {
  const GitProcessCancellationRequest._({
    required this.identity,
    required this.token,
    required this.cause,
  });

  final GitProcessExecutionIdentity identity;
  final GitProcessAttemptToken token;
  final GitProcessCancellationCause cause;
}

typedef GitProcessCancellationResult = ({
  GitProcessCancellationDisposition disposition,
  GitProcessCancellationRequest? request,
});

typedef GitProcessCompletionResult = ({
  GitProcessCompletionDisposition disposition,
  bool isLate,
  GitProcessEffectReceipt? receipt,
});

typedef GitProcessReconciliationResult = ({
  GitProcessReconciliationDisposition disposition,
  GitProcessReconciliationReceipt? receipt,
});

typedef GitProcessReleaseResult = ({
  GitProcessReleaseDisposition disposition,
  GitProcessEffectReceipt? receipt,
});

typedef GitProcessRetirementWork = ({
  List<GitProcessCancellationRequest> cancellationRequests,
  List<GitProcessEffectReceipt> reconciliationRequired,
  int preventedStartCount,
});

enum _ProcessState {
  reserved,
  running,
  completedCommitted,
  reconciliationRequired,
  settledNoEffect,
  released,
  retiredBeforeStart,
  abandonedBeforeStart,
}

final class _ProcessRecord {
  _ProcessRecord(this.identity, this.token);

  final GitProcessExecutionIdentity identity;
  final GitProcessAttemptToken token;
  _ProcessState state = _ProcessState.reserved;
  bool ownerRetired = false;
  GitProcessCancellationRequest? cancellationRequest;
  GitProcessEffectReceipt? receipt;
  GitProcessReconciliationReceipt? reconciliationReceipt;
}

typedef _GitProcessResource = String;

final class GitProcessExecutionCoordinator {
  final Map<GitProcessAttemptToken, _ProcessRecord> _records = {};
  final Map<GitProcessExecutionIdentity, GitProcessAttemptToken>
  _attemptTokens = {};
  final Map<_GitProcessResource, GitProcessAttemptToken> _resourceTokens = {};
  final Set<ChatTurnOwner> _retiredOwners = {};
  var _globallyRetired = false;

  GitProcessReserveResult reserve(GitProcessExecutionIdentity identity) {
    if (_globallyRetired || _retiredOwners.contains(identity.owner)) {
      return (
        disposition: GitProcessReserveDisposition.ownerRetired,
        token: null,
      );
    }
    if (_attemptTokens.containsKey(identity)) {
      return (
        disposition: GitProcessReserveDisposition.attemptConflict,
        token: null,
      );
    }
    final resource = _resource(identity);
    if (_resourceTokens.containsKey(resource)) {
      return (
        disposition: GitProcessReserveDisposition.resourceBusy,
        token: null,
      );
    }

    final token = GitProcessAttemptToken._();
    final record = _ProcessRecord(identity, token);
    _records[token] = record;
    _attemptTokens[identity] = token;
    _resourceTokens[resource] = token;
    return (disposition: GitProcessReserveDisposition.reserved, token: token);
  }

  GitProcessStartDisposition start(
    GitProcessExecutionIdentity identity,
    GitProcessAttemptToken token,
  ) {
    final record = _records[token];
    if (record == null || record.identity != identity) {
      return GitProcessStartDisposition.invalidAttempt;
    }
    if (record.state == _ProcessState.retiredBeforeStart) {
      return GitProcessStartDisposition.ownerRetired;
    }
    if (record.state == _ProcessState.running) {
      return GitProcessStartDisposition.alreadyStarted;
    }
    if (record.state != _ProcessState.reserved) {
      return GitProcessStartDisposition.alreadyCompleted;
    }
    if (_globallyRetired || _retiredOwners.contains(identity.owner)) {
      record
        ..state = _ProcessState.retiredBeforeStart
        ..ownerRetired = true;
      _releaseResource(record);
      return GitProcessStartDisposition.ownerRetired;
    }
    record.state = _ProcessState.running;
    return GitProcessStartDisposition.started;
  }

  GitProcessAbandonDisposition abandonBeforeStart(
    GitProcessExecutionIdentity identity,
    GitProcessAttemptToken token,
  ) {
    final record = _records[token];
    if (record == null || record.identity != identity) {
      return GitProcessAbandonDisposition.invalidAttempt;
    }
    switch (record.state) {
      case _ProcessState.reserved:
        record.state = _ProcessState.abandonedBeforeStart;
        _releaseResource(record);
        return GitProcessAbandonDisposition.abandoned;
      case _ProcessState.abandonedBeforeStart:
        return GitProcessAbandonDisposition.alreadyAbandoned;
      case _ProcessState.running:
        return GitProcessAbandonDisposition.alreadyStarted;
      case _ProcessState.retiredBeforeStart:
        return GitProcessAbandonDisposition.ownerRetired;
      case _ProcessState.completedCommitted:
      case _ProcessState.reconciliationRequired:
      case _ProcessState.settledNoEffect:
      case _ProcessState.released:
        return GitProcessAbandonDisposition.alreadyCompleted;
    }
  }

  GitProcessCancellationResult requestCancellation({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required GitProcessCancellationCause cause,
  }) {
    final record = _records[token];
    if (record == null || record.identity != identity) {
      return (
        disposition: GitProcessCancellationDisposition.invalidAttempt,
        request: null,
      );
    }
    if (record.state == _ProcessState.reserved) {
      return (
        disposition: GitProcessCancellationDisposition.notRunning,
        request: null,
      );
    }
    if (record.state != _ProcessState.running) {
      return (
        disposition: GitProcessCancellationDisposition.alreadyCompleted,
        request: null,
      );
    }
    final existing = record.cancellationRequest;
    if (existing != null) {
      return (
        disposition: GitProcessCancellationDisposition.alreadyRequested,
        request: existing,
      );
    }
    final request = GitProcessCancellationRequest._(
      identity: identity,
      token: token,
      cause: cause,
    );
    record.cancellationRequest = request;
    return (
      disposition: GitProcessCancellationDisposition.requested,
      request: request,
    );
  }

  GitProcessCompletionResult complete({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required GitProcessEffectKind effectKind,
    Map<String, dynamic> effectDetails = const {},
  }) {
    final record = _records[token];
    if (record == null || record.identity != identity) {
      return (
        disposition: GitProcessCompletionDisposition.invalidAttempt,
        isLate: false,
        receipt: null,
      );
    }
    if (record.state == _ProcessState.reserved ||
        record.state == _ProcessState.retiredBeforeStart ||
        record.state == _ProcessState.abandonedBeforeStart) {
      return (
        disposition: GitProcessCompletionDisposition.notStarted,
        isLate: record.ownerRetired,
        receipt: null,
      );
    }
    if (record.state != _ProcessState.running) {
      return (
        disposition: GitProcessCompletionDisposition.alreadyCompleted,
        isLate: record.ownerRetired,
        receipt: record.receipt,
      );
    }

    final isLate =
        record.ownerRetired ||
        _globallyRetired ||
        _retiredOwners.contains(identity.owner);
    if (effectKind == GitProcessEffectKind.noEffect) {
      record.state = _ProcessState.settledNoEffect;
      _releaseResource(record);
      return (
        disposition: GitProcessCompletionDisposition.noEffect,
        isLate: isLate,
        receipt: null,
      );
    }

    final receipt = GitProcessEffectReceipt._(
      identity: identity,
      token: token,
      kind: effectKind,
      details: effectDetails,
    );
    record.receipt = receipt;
    final requiresReconciliation =
        effectKind == GitProcessEffectKind.partialOrUnknown ||
        isLate ||
        record.cancellationRequest != null;
    record.state = requiresReconciliation
        ? _ProcessState.reconciliationRequired
        : _ProcessState.completedCommitted;
    return (
      disposition: requiresReconciliation
          ? GitProcessCompletionDisposition.reconciliationRequired
          : GitProcessCompletionDisposition.effectCommitted,
      isLate: isLate,
      receipt: receipt,
    );
  }

  GitProcessReconciliationResult recordReconciliation({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required GitProcessEffectReceipt effectReceipt,
  }) {
    final record = _records[token];
    if (record == null || record.identity != identity) {
      return (
        disposition: GitProcessReconciliationDisposition.invalidAttempt,
        receipt: null,
      );
    }
    if (!identical(record.receipt, effectReceipt)) {
      return (
        disposition: GitProcessReconciliationDisposition.invalidEffectReceipt,
        receipt: null,
      );
    }
    final existing = record.reconciliationReceipt;
    if (existing != null) {
      return (
        disposition: GitProcessReconciliationDisposition.alreadyRecorded,
        receipt: existing,
      );
    }
    if (record.state != _ProcessState.reconciliationRequired) {
      return (
        disposition: GitProcessReconciliationDisposition.notRequired,
        receipt: null,
      );
    }
    final receipt = GitProcessReconciliationReceipt._(
      identity: identity,
      token: token,
      effectReceipt: effectReceipt,
    );
    record.reconciliationReceipt = receipt;
    return (
      disposition: GitProcessReconciliationDisposition.recorded,
      receipt: receipt,
    );
  }

  GitProcessRequireReconciliationDisposition requireReconciliation({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required GitProcessEffectReceipt effectReceipt,
  }) {
    final record = _records[token];
    if (record == null || record.identity != identity) {
      return GitProcessRequireReconciliationDisposition.invalidAttempt;
    }
    if (!identical(record.receipt, effectReceipt)) {
      return GitProcessRequireReconciliationDisposition.invalidEffectReceipt;
    }
    if (record.state == _ProcessState.reconciliationRequired) {
      return GitProcessRequireReconciliationDisposition.alreadyRequired;
    }
    if (record.state != _ProcessState.completedCommitted) {
      return GitProcessRequireReconciliationDisposition.notCommitted;
    }
    record.state = _ProcessState.reconciliationRequired;
    return GitProcessRequireReconciliationDisposition.required;
  }

  GitProcessReleaseResult release({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    GitProcessReconciliationReceipt? reconciliationReceipt,
  }) {
    final record = _records[token];
    if (record == null || record.identity != identity) {
      return (
        disposition: GitProcessReleaseDisposition.invalidAttempt,
        receipt: null,
      );
    }
    if (record.state == _ProcessState.completedCommitted &&
        (_globallyRetired || _retiredOwners.contains(identity.owner))) {
      record
        ..state = _ProcessState.reconciliationRequired
        ..ownerRetired = true;
    }
    if (record.state == _ProcessState.reconciliationRequired) {
      if (reconciliationReceipt == null) {
        return (
          disposition: GitProcessReleaseDisposition.reconciliationRequired,
          receipt: record.receipt,
        );
      }
      if (!identical(record.reconciliationReceipt, reconciliationReceipt) ||
          !reconciliationReceipt._matches(record)) {
        return (
          disposition:
              GitProcessReleaseDisposition.invalidReconciliationReceipt,
          receipt: record.receipt,
        );
      }
      record.state = _ProcessState.released;
      _releaseResource(record);
      return (
        disposition: GitProcessReleaseDisposition.reconciledAndReleased,
        receipt: record.receipt,
      );
    }
    if (record.state == _ProcessState.completedCommitted) {
      record.state = _ProcessState.released;
      _releaseResource(record);
      return (
        disposition: GitProcessReleaseDisposition.released,
        receipt: record.receipt,
      );
    }
    if (record.state == _ProcessState.reserved ||
        record.state == _ProcessState.running) {
      return (
        disposition: GitProcessReleaseDisposition.notCompleted,
        receipt: null,
      );
    }
    return (
      disposition: GitProcessReleaseDisposition.alreadyReleased,
      receipt: null,
    );
  }

  GitProcessRetirementWork clearOwner(ChatTurnOwner owner) {
    _retiredOwners.add(owner);
    return _retire((record) => record.identity.owner == owner);
  }

  GitProcessRetirementWork clearAll() {
    _globallyRetired = true;
    _retiredOwners.addAll(
      _records.values.map((record) => record.identity.owner),
    );
    return _retire((_) => true);
  }

  GitProcessRetirementWork _retire(
    bool Function(_ProcessRecord record) matches,
  ) {
    final cancellations = <GitProcessCancellationRequest>[];
    final reconciliations = <GitProcessEffectReceipt>[];
    var preventedStarts = 0;
    for (final record in _records.values) {
      if (!matches(record)) continue;
      record.ownerRetired = true;
      switch (record.state) {
        case _ProcessState.reserved:
          record.state = _ProcessState.retiredBeforeStart;
          preventedStarts += 1;
          _releaseResource(record);
        case _ProcessState.running:
          final cancellation =
              record.cancellationRequest ??
              GitProcessCancellationRequest._(
                identity: record.identity,
                token: record.token,
                cause: GitProcessCancellationCause.ownerRetired,
              );
          record.cancellationRequest = cancellation;
          cancellations.add(cancellation);
        case _ProcessState.completedCommitted:
          record.state = _ProcessState.reconciliationRequired;
          reconciliations.add(record.receipt!);
        case _ProcessState.reconciliationRequired:
          reconciliations.add(record.receipt!);
        case _ProcessState.settledNoEffect:
        case _ProcessState.released:
        case _ProcessState.retiredBeforeStart:
        case _ProcessState.abandonedBeforeStart:
          break;
      }
    }
    return (
      cancellationRequests: List.unmodifiable(cancellations),
      reconciliationRequired: List.unmodifiable(reconciliations),
      preventedStartCount: preventedStarts,
    );
  }

  _GitProcessResource _resource(GitProcessExecutionIdentity identity) {
    return identity.repositoryIdentity;
  }

  void _releaseResource(_ProcessRecord record) {
    final resource = _resource(record.identity);
    if (_resourceTokens[resource] == record.token) {
      _resourceTokens.remove(resource);
    }
  }
}
