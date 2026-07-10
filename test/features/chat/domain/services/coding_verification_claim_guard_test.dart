import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_claim_guard.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_service.dart';

void main() {
  const guard = CodingVerificationClaimGuard();

  ToolResultInfo evidence({
    required int passed,
    required int failed,
    required int skipped,
  }) {
    return ToolResultInfo(
      id: 'verification-evidence',
      name: CodingVerificationFeedbackService.evidenceToolName,
      arguments: const {},
      result: jsonEncode({
        'schema': CodingVerificationFeedbackService.evidenceSchemaName,
        'validation_status': failed == 0 ? 'passed' : 'failed',
        'counts': {'passed': passed, 'failed': failed, 'skipped': skipped},
        'verification': {
          'executable': 'dart',
          'arguments': ['test', 'test'],
        },
      }),
    );
  }

  test('reports a fraction claim that disagrees with recorded counts', () {
    final assessment = guard.assess(
      candidateResponse: 'Test result: 20/20 passed.',
      toolResults: [evidence(passed: 1, failed: 0, skipped: 0)],
    );

    expect(assessment.hasMismatch, isTrue);
    expect(assessment.mismatch!.claimedPassedCount, 20);
    expect(assessment.mismatch!.claimedTotalCount, 20);
    expect(assessment.mismatch!.actualPassedCount, 1);
    expect(assessment.buildNotice(), contains('20/20 passing tests'));
    expect(assessment.buildNotice(), contains('1 passed'));
    expect(assessment.buildNotice(), contains('`dart test test`'));
  });

  test('reports Japanese verification count phrasing', () {
    final assessment = guard.assess(
      candidateResponse: '\u30c6\u30b9\u30c8\u7d50\u679c: 20/20\u6210\u529f',
      toolResults: [evidence(passed: 1, failed: 0, skipped: 0)],
    );

    expect(assessment.hasMismatch, isTrue);
  });

  test('reports natural Japanese passed-count phrasing', () {
    const responses = [
      '\u30c6\u30b9\u30c8\u304c16\u4ef6\u5168\u3066\u30d1\u30b9\u3057\u307e\u3057\u305f\u3002',
      '\u30c6\u30b9\u30c8\u304c16\u4ef6\u3059\u3079\u3066\u30d1\u30b9\u3057\u307e\u3057\u305f\u3002',
      '\u30c6\u30b9\u30c8\u304c16\u4ef6\u5168\u90e8\u30d1\u30b9\u3057\u307e\u3057\u305f\u3002',
      '16\u4ef6\u6210\u529f\u3057\u307e\u3057\u305f\u3002',
    ];

    for (final response in responses) {
      final assessment = guard.assess(
        candidateResponse: response,
        toolResults: [evidence(passed: 1, failed: 0, skipped: 0)],
      );

      expect(
        assessment.hasMismatch,
        isTrue,
        reason: 'Expected the claim guard to inspect: $response',
      );
      expect(assessment.mismatch!.claimedPassedCount, 16);
    }
  });

  test('reports a standalone passed count that disagrees with evidence', () {
    final assessment = guard.assess(
      candidateResponse: 'All 12 tests passed.',
      toolResults: [evidence(passed: 2, failed: 0, skipped: 1)],
    );

    expect(assessment.hasMismatch, isTrue);
    expect(assessment.mismatch!.claimedPassedCount, 12);
    expect(assessment.mismatch!.claimedTotalCount, isNull);
  });

  test('stays silent when the reported counts match', () {
    final assessment = guard.assess(
      candidateResponse: 'Test result: 2/3 passed.',
      toolResults: [evidence(passed: 2, failed: 1, skipped: 0)],
    );

    expect(assessment.hasMismatch, isFalse);
  });

  test('stays silent without verification context or evidence', () {
    expect(
      guard
          .assess(
            candidateResponse: 'Implemented 20/20 requested items.',
            toolResults: [evidence(passed: 1, failed: 0, skipped: 0)],
          )
          .hasMismatch,
      isFalse,
    );
    expect(
      guard
          .assess(
            candidateResponse: 'All 20 tests passed.',
            toolResults: const [],
          )
          .hasMismatch,
      isFalse,
    );
  });

  test('stays silent for unrelated Japanese numeric counts', () {
    const responses = [
      '16\u4ef6\u3092\u66f4\u65b0\u3057\u307e\u3057\u305f\u3002',
      '16\u4ef6\u30d1\u30b9\u30ef\u30fc\u30c9\u3092\u66f4\u65b0\u3057\u307e\u3057\u305f\u3002',
      '16/20\u30d1\u30b9\u30ef\u30fc\u30c9\u3092\u66f4\u65b0\u3057\u307e\u3057\u305f\u3002',
    ];

    for (final response in responses) {
      final assessment = guard.assess(
        candidateResponse: response,
        toolResults: [evidence(passed: 1, failed: 0, skipped: 0)],
      );

      expect(
        assessment.hasMismatch,
        isFalse,
        reason: 'Expected an unrelated count to be ignored: $response',
      );
    }
  });

  test('ignores count examples in fenced code', () {
    final assessment = guard.assess(
      candidateResponse: '```text\nTest result: 20/20 passed.\n```',
      toolResults: [evidence(passed: 1, failed: 0, skipped: 0)],
    );

    expect(assessment.hasMismatch, isFalse);
  });

  test('uses the latest valid evidence result', () {
    final assessment = guard.assess(
      candidateResponse: 'All 3 tests passed.',
      toolResults: [
        evidence(passed: 1, failed: 0, skipped: 0),
        evidence(passed: 3, failed: 0, skipped: 0),
      ],
    );

    expect(assessment.hasMismatch, isFalse);
  });
}
