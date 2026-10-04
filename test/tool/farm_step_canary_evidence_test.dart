import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/canaries/support/farm_step_payload_guard.dart';
import '../../tool/farm_step_canary_evidence.dart';

void main() {
  Map<String, dynamic> summary() => {
    'result': 'passed',
    'passedCount': farmStepScenarioNames.length,
    'failedCount': 0,
    'skippedCount': 0,
  };
  Map<String, Map<String, dynamic>> cases() => {
    for (final name in farmStepScenarioNames)
      name: {
        'scenario': name,
        'passed': true,
        'faultPreludeUsed': true,
        'liveHttp': true,
        'livePrimaryCalls': 1,
        'liveMemoryCalls': 1,
        if (name == 'stdinVerification' ||
            name == 'failedStdinVerification') ...{
          'completedSubtasks': name == 'stdinVerification'
              ? ['first', 'second']
              : [],
          'finalBoundaryReached': name == 'stdinVerification' ? 1 : 0,
          'stdinEvidence': {
            'changedPath': 'README.md',
            'changed': true,
            'readmeShorthandPreludeUsed': true,
            'verificationAfterMutation': true,
            'verificationCommand': ".venv/bin/python - <<'PY'\nassert True\nPY",
            'exitCodes': name == 'stdinVerification' ? [0, 0] : [1],
          },
        },
      },
  };
  test('requires all six live evidence records', () {
    expect(farmStepEvidenceGaps(summary(), cases()), isEmpty);
    final missing = cases()..remove('unissuedCommand');
    expect(
      farmStepEvidenceGaps(summary(), missing).single,
      contains('unissuedCommand'),
    );
  });
  test(
    'stdin cases require ordered mutation, fresh execution and progression',
    () {
      for (final name in ['stdinVerification', 'failedStdinVerification']) {
        for (final field in [
          'changed',
          'readmeShorthandPreludeUsed',
          'verificationAfterMutation',
          'exitCodes',
          'verificationCommand',
        ]) {
          final records = cases();
          (records[name]!['stdinEvidence'] as Map).remove(field);
          expect(
            farmStepEvidenceGaps(summary(), records),
            contains(contains(name)),
          );
        }
        final records = cases();
        records[name]!['finalBoundaryReached'] = name == 'stdinVerification'
            ? 0
            : 1;
        expect(
          farmStepEvidenceGaps(summary(), records),
          contains(contains(name)),
        );
      }
    },
  );
  test('missing live evidence downgrades the published summary', () {
    final input = {
      ...summary(),
      'mainReadiness': {'status': 'ready'},
    };
    final missing = cases()..remove('unissuedCommand');
    final output = reconcileFarmStepEvidence(input, missing);
    expect(output['result'], 'failed');
    expect(output['flutterResult'], 'passed');
    expect((output['mainReadiness'] as Map)['status'], 'blocked');
    expect(input['result'], 'passed');
    expect((input['mainReadiness'] as Map)['status'], 'ready');
    expect(reconcileFarmStepEvidence(input, cases())['result'], 'passed');
  });
  test('stdin exit codes must prove the expected success or failure', () {
    for (final name in ['stdinVerification', 'failedStdinVerification']) {
      for (final codes
          in name == 'stdinVerification'
              ? [
                  <int>[],
                  [0],
                  [1, 0],
                  [null, null],
                ]
              : [
                  <int>[],
                  [0],
                  [1, 0],
                  [null],
                ]) {
        final records = cases();
        (records[name]!['stdinEvidence'] as Map)['exitCodes'] = codes;
        expect(
          farmStepEvidenceGaps(summary(), records),
          contains(contains(name)),
        );
      }
    }
  });

  test('skipped and failed tests never qualify as live evidence', () {
    for (final changed in [
      {'result': 'skipped', 'passedCount': 0, 'skippedCount': 4},
      {'result': 'failed', 'passedCount': 3, 'failedCount': 1},
      {'passedCount': 3, 'skippedCount': 1},
    ]) {
      expect(
        farmStepEvidenceGaps({...summary(), ...changed}, cases()),
        isNotEmpty,
      );
    }
  });
  test('model-free recovery or memory cannot pass the gate', () {
    for (final field in ['livePrimaryCalls', 'liveMemoryCalls']) {
      final scripted = cases();
      scripted['missingExecution']![field] = 0;
      expect(
        farmStepEvidenceGaps(summary(), scripted).single,
        contains('missingExecution'),
      );
    }
    final offline = cases();
    offline['missingExecution']!['liveHttp'] = false;
    expect(farmStepEvidenceGaps(summary(), offline), isNotEmpty);
  });
  test('unactivated faults and unsuccessful persistence fail closed', () {
    for (final field in ['faultPreludeUsed', 'passed']) {
      final unproven = cases();
      unproven['environmentLookup']![field] = false;
      expect(
        farmStepEvidenceGaps(summary(), unproven).single,
        contains('environmentLookup'),
      );
    }
  });
  test(
    'outbound guard rejects user-home and repository context before HTTP',
    () {
      for (final content in [
        '/Users/canary/private.md',
        'Caverno agent guide',
        '.caverno/session_logs/private.jsonl',
      ]) {
        expect(
          () => guardFarmStepPayload([
            Message(
              id: 'guard',
              role: MessageRole.user,
              content: content,
              timestamp: DateTime(2026),
            ),
          ]),
          throwsStateError,
        );
      }
      expect(
        () => guardFarmStepPayload([
          Message(
            id: 'guard',
            role: MessageRole.user,
            content: 'Synthetic /private/tmp/project/policy.md',
            timestamp: DateTime(2026),
          ),
        ]),
        returnsNormally,
      );
    },
  );
}
