import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_presentation.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('commandSummary', () {
    test('prefers the selected command', () {
      final snapshot = _snapshot(
        selectedAttempt: _attempt(
          executable: 'flutter',
          arguments: const ['test', '--machine', 'test/main_test.dart'],
        ),
        targetBatches: const [
          CodingVerificationTargetBatch(
            packageRoot: '/workspace',
            targets: ['ignored.dart'],
          ),
        ],
      );

      expect(
        CodingVerificationFeedbackPresentation.commandSummary(snapshot),
        'flutter test --machine test/main_test.dart',
      );
    });

    test('falls back to target batches in stable order', () {
      final snapshot = _snapshot(
        targetBatches: const [
          CodingVerificationTargetBatch(
            packageRoot: '/workspace/a',
            targets: ['test/a_test.dart', 'test/b_test.dart'],
          ),
          CodingVerificationTargetBatch(
            packageRoot: '/workspace/b',
            targets: ['test/c_test.dart'],
          ),
        ],
      );

      expect(
        CodingVerificationFeedbackPresentation.commandSummary(snapshot),
        'coding verification '
        'test/a_test.dart test/b_test.dart test/c_test.dart',
      );
      expect(
        CodingVerificationFeedbackPresentation.commandSummary(_snapshot()),
        'coding verification',
      );
    });
  });

  group('progress summaries', () {
    test('formats passed, failed, skipped, and empty counts', () {
      final counted = _snapshot(
        validationStatus: ConversationExecutionValidationStatus.passed,
        passedCount: 4,
        failedCount: 2,
        skippedCount: 1,
      );

      expect(
        CodingVerificationFeedbackPresentation.countsSummary(counted),
        '4 passed, 2 failed, 1 skipped',
      );
      expect(
        CodingVerificationFeedbackPresentation.progressSummary(counted),
        'Coding verification passed (4 passed, 2 failed, 1 skipped).',
      );
      expect(
        CodingVerificationFeedbackPresentation.countsSummary(_snapshot()),
        isEmpty,
      );
      expect(
        CodingVerificationFeedbackPresentation.progressSummary(
          _snapshot(
            validationStatus: ConversationExecutionValidationStatus.failed,
            failedCount: 1,
          ),
        ),
        'Coding verification failed (1 failed).',
      );
    });

    test('formats inconclusive snapshots with and without a reason', () {
      expect(
        CodingVerificationFeedbackPresentation.progressSummary(
          _snapshot(
            validationStatus: ConversationExecutionValidationStatus.unknown,
          ),
        ),
        'Coding verification was inconclusive.',
      );
      expect(
        CodingVerificationFeedbackPresentation.progressSummary(
          _snapshot(
            validationStatus: ConversationExecutionValidationStatus.unknown,
            reason: 'No Dart package was found',
            skippedCount: 2,
          ),
        ),
        'Coding verification was inconclusive: No Dart package was found '
        '(2 skipped).',
      );
    });
  });

  group('validationSummary', () {
    test('relativizes and formats a located failure', () {
      final snapshot = _snapshot(
        validationStatus: ConversationExecutionValidationStatus.failed,
        failures: const [
          CodingVerificationFailure(
            testName: '  value returns two  ',
            message: '  Expected: <2> Actual: <1>  ',
            absolutePath: '/workspace/test/main_test.dart',
            line: 4,
          ),
        ],
      );

      expect(
        CodingVerificationFeedbackPresentation.validationSummary(snapshot),
        'test/main_test.dart:line 4 value returns two: '
        'Expected: <2> Actual: <1>',
      );
    });

    test('uses the failure fallback without a location or label', () {
      final snapshot = _snapshot(
        validationStatus: ConversationExecutionValidationStatus.failed,
        failures: const [
          CodingVerificationFailure(testName: ' ', message: ' '),
        ],
      );

      expect(
        CodingVerificationFeedbackPresentation.validationSummary(snapshot),
        'Test failed.',
      );
    });

    test('falls back to progress for non-failing or empty snapshots', () {
      expect(
        CodingVerificationFeedbackPresentation.validationSummary(
          _snapshot(
            validationStatus: ConversationExecutionValidationStatus.failed,
            failedCount: 1,
          ),
        ),
        'Coding verification failed (1 failed).',
      );
      expect(
        CodingVerificationFeedbackPresentation.validationSummary(
          _snapshot(
            validationStatus: ConversationExecutionValidationStatus.passed,
            passedCount: 1,
          ),
        ),
        'Coding verification passed (1 passed).',
      );
    });
  });

  group('shouldVerifyCompletionClaim', () {
    test('accepts completion evidence and done phrasing', () {
      for (final response in const [
        'Task complete',
        'Tests passed',
        'The requested change is DONE.',
      ]) {
        expect(
          CodingVerificationFeedbackPresentation.shouldVerifyCompletionClaim(
            response,
          ),
          isTrue,
          reason: response,
        );
      }
    });

    test('rejects empty, incomplete, and weak handoff text', () {
      for (final response in const [
        '',
        '   ',
        'The task is not complete.',
        'The task is not completed.',
        'The task remains incomplete.',
        'Next task is ready.',
      ]) {
        expect(
          CodingVerificationFeedbackPresentation.shouldVerifyCompletionClaim(
            response,
          ),
          isFalse,
          reason: response,
        );
      }
    });
  });

  group('failureSignature', () {
    test('keeps stable provider, status, and failure keys', () {
      final feedback = _feedback({
        'provider': 'dart_test_runner',
        'validation_status': 'failed',
        'failing_tests': [
          {
            'relative_path': 'test/a_test.dart',
            'path': '/workspace/test/a_test.dart',
            'test_name': 'first test',
            'line': 4,
            'column': 9,
            'message': 'first failure',
            'ignored': true,
          },
          {
            'path': '/workspace/test/b_test.dart',
            'test_name': 'second test',
            'line': null,
            'column': null,
            'message': 'second failure',
          },
        ],
      });

      expect(
        CodingVerificationFeedbackPresentation.failureSignature(feedback),
        jsonEncode({
          'provider': 'dart_test_runner',
          'validation_status': 'failed',
          'failures': [
            {
              'relative_path': 'test/a_test.dart',
              'test_name': 'first test',
              'line': 4,
              'column': 9,
              'message': 'first failure',
            },
            {
              'relative_path': '/workspace/test/b_test.dart',
              'test_name': 'second test',
              'line': null,
              'column': null,
              'message': 'second failure',
            },
          ],
        }),
      );
    });

    test('rejects malformed, empty, and non-map failures', () {
      expect(
        CodingVerificationFeedbackPresentation.failureSignature(
          _rawFeedback('{'),
        ),
        isNull,
      );
      expect(
        CodingVerificationFeedbackPresentation.failureSignature(
          _rawFeedback('[]'),
        ),
        isNull,
      );
      expect(
        CodingVerificationFeedbackPresentation.failureSignature(_feedback({})),
        isNull,
      );
      expect(
        CodingVerificationFeedbackPresentation.failureSignature(
          _feedback({'failing_tests': []}),
        ),
        isNull,
      );
      expect(
        CodingVerificationFeedbackPresentation.failureSignature(
          _feedback({
            'failing_tests': ['not a map'],
          }),
        ),
        isNull,
      );
    });
  });

  group('convergenceBlocker', () {
    test('formats and clips the first five failing tests', () {
      final failures = [
        {
          'relative_path': 'test/one_test.dart',
          'test_name': 'first',
          'line': 3,
          'message': 'one failed',
        },
        {
          'path': '/workspace/test/two_test.dart',
          'test_name': '',
          'message': '',
        },
        {
          'relative_path': '',
          'test_name': 'third',
          'line': 8,
          'message': 'three failed',
        },
        {'relative_path': 4, 'test_name': 5, 'message': 'four failed'},
        {
          'relative_path': 'test/five_test.dart',
          'test_name': 'fifth',
          'message': 'five failed',
        },
        {
          'relative_path': 'test/six_test.dart',
          'test_name': 'sixth',
          'message': 'must be clipped',
        },
      ];

      final blocker = CodingVerificationFeedbackPresentation.convergenceBlocker(
        _feedback({'failing_tests': failures}),
        maxRepairAttempts: 3,
      );

      expect(
        blocker,
        'The coding task is not complete. The same failing tests persisted '
        'after 3 repair attempts, so I am stopping the automatic repair loop.\n'
        '\n'
        'Remaining failing tests:\n'
        '- test/one_test.dart:line 3 first: one failed\n'
        '- /workspace/test/two_test.dart: Test failed.\n'
        '- line 8 third: three failed\n'
        '- four failed\n'
        '- test/five_test.dart fifth: five failed',
      );
      expect(blocker, isNot(contains('must be clipped')));
    });

    test('ignores non-map entries and handles missing payloads', () {
      const base =
          'The coding task is not complete. The same failing tests persisted '
          'after 2 repair attempts, so I am stopping the automatic repair loop.';

      expect(
        CodingVerificationFeedbackPresentation.convergenceBlocker(
          _rawFeedback('{'),
          maxRepairAttempts: 2,
        ),
        base,
      );
      expect(
        CodingVerificationFeedbackPresentation.convergenceBlocker(
          _feedback({'failing_tests': []}),
          maxRepairAttempts: 2,
        ),
        base,
      );
      expect(
        CodingVerificationFeedbackPresentation.convergenceBlocker(
          _feedback({
            'failing_tests': ['not a map'],
          }),
          maxRepairAttempts: 2,
        ),
        '$base\n\nRemaining failing tests:',
      );
    });
  });

  group('telemetrySummary', () {
    test('returns every persisted telemetry field in stable order', () {
      final feedback = _feedback({
        'provider': 'dart_test_runner',
        'trigger': 'completionClaim',
        'validation_status': 'failed',
        'changed_paths': ['lib/main.dart'],
        'counts': {'passed': 7, 'failed': 2, 'skipped': 1},
        'telemetry': {
          'duration_ms': 125,
          'command_attempt_count': 3,
          'fallback_command_count': 2,
          'timed_out_command_count': 1,
          'start_error_command_count': 1,
        },
      }, name: 'dart_test_feedback');

      final summary = CodingVerificationFeedbackPresentation.telemetrySummary(
        feedback,
      );

      expect(summary, {
        'toolName': 'dart_test_feedback',
        'provider': 'dart_test_runner',
        'trigger': 'completionClaim',
        'validationStatus': 'failed',
        'files': ['lib/main.dart'],
        'passedCount': 7,
        'failedCount': 2,
        'skippedCount': 1,
        'durationMs': 125,
        'commandAttemptCount': 3,
        'fallbackCommandCount': 2,
        'timedOutCommandCount': 1,
        'startErrorCommandCount': 1,
      });
      expect(
        jsonEncode(summary),
        '{"toolName":"dart_test_feedback","provider":"dart_test_runner",'
        '"trigger":"completionClaim","validationStatus":"failed",'
        '"files":["lib/main.dart"],"passedCount":7,"failedCount":2,'
        '"skippedCount":1,"durationMs":125,"commandAttemptCount":3,'
        '"fallbackCommandCount":2,"timedOutCommandCount":1,'
        '"startErrorCommandCount":1}',
      );
    });

    test('omits malformed optional sections and rejects malformed JSON', () {
      expect(
        CodingVerificationFeedbackPresentation.telemetrySummary(
          _feedback({
            'provider': 'provider',
            'counts': [],
            'telemetry': 'invalid',
          }),
        ),
        {
          'toolName': 'dart_test_feedback',
          'provider': 'provider',
          'trigger': null,
          'validationStatus': null,
          'files': null,
        },
      );
      expect(
        CodingVerificationFeedbackPresentation.telemetrySummary(
          _rawFeedback('[]'),
        ),
        isNull,
      );
    });
  });
}

CodingVerificationSnapshot _snapshot({
  ConversationExecutionValidationStatus validationStatus =
      ConversationExecutionValidationStatus.passed,
  List<CodingVerificationTargetBatch> targetBatches = const [],
  List<CodingVerificationFailure> failures = const [],
  int passedCount = 0,
  int failedCount = 0,
  int skippedCount = 0,
  String? reason,
  CodingVerificationCommandAttempt? selectedAttempt,
}) {
  return CodingVerificationSnapshot(
    providerName: 'dart_test_runner',
    projectRoot: '/workspace',
    changedPaths: const ['lib/main.dart'],
    trigger: CodingVerificationTrigger.completionClaim,
    validationStatus: validationStatus,
    targetBatches: targetBatches,
    failures: failures,
    telemetry: const CodingVerificationTelemetry(durationMs: 0, attempts: []),
    passedCount: passedCount,
    failedCount: failedCount,
    skippedCount: skippedCount,
    reason: reason,
    selectedAttempt: selectedAttempt,
  );
}

CodingVerificationCommandAttempt _attempt({
  required String executable,
  required List<String> arguments,
}) {
  return CodingVerificationCommandAttempt(
    command: CodingVerificationCommand(
      executable: executable,
      arguments: arguments,
      workingDirectory: '/workspace',
    ),
    exitCode: 0,
    durationMs: 10,
    timedOut: false,
    validationStatus: ConversationExecutionValidationStatus.passed,
    passedCount: 1,
    failedCount: 0,
    skippedCount: 0,
  );
}

ToolResultInfo _feedback(
  Map<String, Object?> payload, {
  String name = 'dart_test_feedback',
}) {
  return _rawFeedback(jsonEncode(payload), name: name);
}

ToolResultInfo _rawFeedback(
  String result, {
  String name = 'dart_test_feedback',
}) {
  return ToolResultInfo(
    id: 'feedback',
    name: name,
    arguments: const {},
    result: result,
  );
}
