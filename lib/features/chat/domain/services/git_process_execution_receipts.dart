part of 'git_process_execution_coordinator.dart';

Map<String, dynamic> _freezeDetails(Map<String, dynamic> source) {
  return ImmutableJsonSnapshot.freezeMap(source, argumentName: 'details');
}

final class GitProcessEffectReceipt {
  GitProcessEffectReceipt._({
    required this.identity,
    required this.token,
    required this.kind,
    required Map<String, dynamic> details,
  }) : details = _freezeDetails(details);

  final GitProcessExecutionIdentity identity;
  final GitProcessAttemptToken token;
  final GitProcessEffectKind kind;
  final Map<String, dynamic> details;
}

final class GitProcessReconciliationReceipt {
  GitProcessReconciliationReceipt._({
    required GitProcessExecutionIdentity identity,
    required GitProcessAttemptToken token,
    required GitProcessEffectReceipt effectReceipt,
  }) : _identity = identity,
       _token = token,
       _effectReceipt = effectReceipt;

  final GitProcessExecutionIdentity _identity;
  final GitProcessAttemptToken _token;
  final GitProcessEffectReceipt _effectReceipt;

  bool _matches(_ProcessRecord record) {
    return _identity == record.identity &&
        identical(_token, record.token) &&
        identical(_effectReceipt, record.receipt);
  }

  @override
  String toString() => 'GitProcessReconciliationReceipt(<opaque>)';
}
