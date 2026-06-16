import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_service.dart';
import 'package:caverno/features/maintenance/data/model_edit_failure_trace_extractor.dart';
import 'package:caverno/features/maintenance/domain/services/failure_trace_miner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const extractor = ModelEditFailureTraceExtractor();

  test('emits one trace per recorded edit-mismatch failure', () {
    final traces = extractor.extract(
      caseId: 'model-x',
      profileMetadata: const {
        ModelEditApplyTelemetryService.editMismatchFailuresKey: '3',
        ModelEditApplyTelemetryService.malformedRequestFailuresKey: '1',
      },
    );

    // Feeding the miner reproduces the cluster support.
    final clusters = const FailureTraceMiner().mine(traces);
    final stale = clusters.firstWhere(
      (c) => c.signature.mechanism == 'stale_old_text',
    );
    expect(stale.support, 3);
    expect(stale.signature.terminalCause, 'edit_apply_failed');
    final malformed = clusters.firstWhere(
      (c) => c.signature.mechanism == 'malformed_tool_call',
    );
    expect(malformed.support, 1);
  });

  test('ignores zero / missing / non-numeric counters', () {
    final traces = extractor.extract(
      caseId: 'model-x',
      profileMetadata: const {
        ModelEditApplyTelemetryService.editMismatchFailuresKey: '0',
        ModelEditApplyTelemetryService.multipleMatchFailuresKey: 'oops',
      },
    );
    expect(traces, isEmpty);
  });

  test('caps traces per kind to avoid an unbounded list', () {
    const capped = ModelEditFailureTraceExtractor(maxTracesPerKind: 5);
    final traces = capped.extract(
      caseId: 'model-x',
      profileMetadata: const {
        ModelEditApplyTelemetryService.editMismatchFailuresKey: '1000',
      },
    );
    expect(traces, hasLength(5));
  });
}
