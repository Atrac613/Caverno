import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';

void main() {
  test('serializes sampler calibration trials in diagnostic reports', () {
    final report = LiveLlmDiagnosticReport(
      startedAt: DateTime.utc(2026, 6, 12),
      baseUrl: 'http://localhost:1234/v1',
      model: 'sampler-model',
      demoMode: false,
      mcpEnabled: true,
      samplerCalibrationTrials: const [
        LiveLlmDiagnosticSamplerTrial(
          requestClass: 'toolLoop',
          temperature: 0.2,
          passed: true,
          jsonRepairEventCount: 1,
          malformedToolCallCount: 2,
          editApplyFailureCount: 3,
          repetitionDetected: true,
        ),
        LiveLlmDiagnosticSamplerTrial(
          requestClass: 'toolLoop',
          temperature: 0.4,
          passed: false,
          malformedToolCallCount: -5,
        ),
      ],
    );

    final updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: 'instruction_echo',
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'JSON ok.',
      ),
    );
    final json = updated.toJson();

    expect(updated.samplerCalibrationTrials, hasLength(2));
    expect(json['samplerCalibrationTrials'], [
      {
        'requestClass': 'toolLoop',
        'temperature': 0.2,
        'passed': true,
        'jsonRepairEventCount': 1,
        'malformedToolCallCount': 2,
        'editApplyFailureCount': 3,
        'repetitionDetected': true,
      },
      {'requestClass': 'toolLoop', 'temperature': 0.4, 'passed': false},
    ]);
    expect(json['samplerCalibrationSummary'], {
      'toolLoop': {
        'trialCount': 2,
        'passedCount': 1,
        'candidateTemperatures': [0.2, 0.4],
        'jsonRepairEventCount': 1,
        'malformedToolCallCount': 2,
        'editApplyFailureCount': 3,
        'repetitionCount': 1,
      },
    });
  });
}
