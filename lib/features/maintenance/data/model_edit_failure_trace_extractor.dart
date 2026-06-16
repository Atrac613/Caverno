import '../../chat/domain/services/model_edit_apply_telemetry_service.dart';
import '../domain/services/failure_trace_miner.dart';

class _EditFailureKind {
  const _EditFailureKind(this.metadataKey, this.mechanism, this.symptom);
  final String metadataKey;
  final String mechanism;
  final String symptom;
}

/// LL17 trace extraction: turns the LL15 edit-apply failure-kind counters stored
/// on a model's capability profile into [FailureTrace]s the miner can cluster.
///
/// The counters are aggregate (per model, not per case), so each kind emits as
/// many traces as its count (capped), giving the miner the right cluster
/// support. The mechanisms line up with [FailureTraceMiner] / the proposer, so
/// e.g. an `editMismatch` count flows through to a stale-old-text proposal.
class ModelEditFailureTraceExtractor {
  const ModelEditFailureTraceExtractor({this.maxTracesPerKind = 50});

  /// Cap on traces emitted per failure kind, so a pathological counter cannot
  /// produce an unbounded list.
  final int maxTracesPerKind;

  static const _kinds = <_EditFailureKind>[
    _EditFailureKind(
      ModelEditApplyTelemetryService.editMismatchFailuresKey,
      'stale_old_text',
      'old_text did not match',
    ),
    _EditFailureKind(
      ModelEditApplyTelemetryService.multipleMatchFailuresKey,
      'ambiguous_old_text',
      'old_text matched multiple locations',
    ),
    _EditFailureKind(
      ModelEditApplyTelemetryService.malformedRequestFailuresKey,
      'malformed_tool_call',
      'malformed edit request',
    ),
    _EditFailureKind(
      ModelEditApplyTelemetryService.missingFileFailuresKey,
      'missing_file',
      'target file not found',
    ),
    _EditFailureKind(
      ModelEditApplyTelemetryService.otherFailuresKey,
      'other',
      'other edit failure',
    ),
  ];

  List<FailureTrace> extract({
    required String caseId,
    required Map<String, String> profileMetadata,
  }) {
    final traces = <FailureTrace>[];
    for (final kind in _kinds) {
      final count = int.tryParse(profileMetadata[kind.metadataKey] ?? '') ?? 0;
      final emit = count.clamp(0, maxTracesPerKind);
      for (var i = 0; i < emit; i++) {
        traces.add(
          FailureTrace(
            caseId: caseId,
            signature: FailureSignature(
              terminalCause: 'edit_apply_failed',
              causalStatus: 'edit_rejected',
              mechanism: kind.mechanism,
            ),
            symptom: kind.symptom,
          ),
        );
      }
    }
    return traces;
  }
}
