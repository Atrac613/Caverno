import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test('records successful edit_file applications', () {
    final updated = ModelEditApplyTelemetryService.recordToolResult(
      profile: _profile(),
      observedAt: DateTime.utc(2026, 6, 14, 1),
      toolResult: _toolResult('{"path":"/tmp/a.dart","replacements":1}'),
    )!;

    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.attemptsKey],
      '1',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.successesKey],
      '1',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.failuresKey],
      '0',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.failureRateKey],
      '0.000',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.lastOutcomeKey],
      ModelEditApplyOutcome.success.name,
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.lastObservedAtKey],
      '2026-06-14T01:00:00.000Z',
    );
  });

  test('classifies old_text mismatch failures', () {
    final updated = ModelEditApplyTelemetryService.recordToolResult(
      profile: _profile(
        metadata: const {
          ModelEditApplyTelemetryService.attemptsKey: '1',
          ModelEditApplyTelemetryService.successesKey: '1',
          ModelEditApplyTelemetryService.failuresKey: '0',
        },
      ),
      toolResult: _toolResult(
        '{"error":"old_text was not found in the target file","path":"/tmp/a.dart"}',
      ),
    )!;

    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.attemptsKey],
      '2',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.successesKey],
      '1',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.failuresKey],
      '1',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.failureRateKey],
      '0.500',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService
          .editMismatchFailuresKey],
      '1',
    );
    expect(
      updated.probeMetadata[ModelEditApplyTelemetryService.lastOutcomeKey],
      ModelEditApplyOutcome.editMismatch.name,
    );
  });

  test('classifies multiple match and malformed request failures', () {
    final multiple = ModelEditApplyTelemetryService.classifyToolResult(
      _toolResult(
        '{"error":"old_text matched multiple locations. Set replace_all=true or make the target text more specific."}',
      ),
    );
    final malformed = ModelEditApplyTelemetryService.classifyToolResult(
      _toolResult('Error: path is required'),
    );

    expect(multiple!.outcome, ModelEditApplyOutcome.multipleMatches);
    expect(malformed!.outcome, ModelEditApplyOutcome.malformedRequest);
  });

  test('ignores non-edit and approval-denied results', () {
    final nonEdit = ModelEditApplyTelemetryService.recordToolResult(
      profile: _profile(),
      toolResult: ToolResultInfo(
        id: 'tool-1',
        name: 'read_file',
        arguments: const {},
        result: '{"path":"/tmp/a.dart"}',
      ),
    );
    final denied = ModelEditApplyTelemetryService.recordToolResult(
      profile: _profile(),
      toolResult: _toolResult('Error: User denied file edit'),
    );

    expect(nonEdit, isNull);
    expect(denied, isNull);
  });

  test('ignores external JSON access failures', () {
    final updated = ModelEditApplyTelemetryService.recordToolResult(
      profile: _profile(),
      toolResult: _toolResult(
        '{"error":"Failed to restore access to the selected coding project.","code":"bookmark_restore_failed","path":"/tmp/a.dart"}',
      ),
    );

    expect(updated, isNull);
  });

  test('builds a prompt failure-rate line after multiple attempts', () {
    final line = ModelEditApplyTelemetryService.promptFailureRateLine(
      _profile(
        metadata: const {
          ModelEditApplyTelemetryService.attemptsKey: '4',
          ModelEditApplyTelemetryService.failureRateKey: '0.250',
        },
      ),
    );

    expect(line, contains('25.0% over 4 attempts'));
    expect(line, contains('old_text'));
  });
}

ModelCapabilityProfile _profile({Map<String, String> metadata = const {}}) {
  return ModelCapabilityProfile(
    id: '',
    baseUrl: 'http://localhost:1234/v1',
    model: 'weak-model',
    probeMetadata: metadata,
  ).normalizedForPersistence();
}

ToolResultInfo _toolResult(String result) {
  return ToolResultInfo(
    id: 'tool-1',
    name: 'edit_file',
    arguments: const {'path': '/tmp/a.dart'},
    result: result,
  );
}
