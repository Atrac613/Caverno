import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/code_unit_text_scan.dart';
import 'package:caverno/features/chat/domain/services/tool_terminal_response_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved validation final text never retains printed or suppressed calls', () {
    final policy = _policy(
      looksLikePendingToolActionResponse: (value) => value.contains('I will'),
    );
    for (final text in [
      'All tests passed. I will check the CLI.\n<tool_call><function=local_execute_command><parameter=command>python3 count_field.py field sample.jsonl</parameter></function></tool_call>',
      'I will run another check. <tool_call>{"name":"run_tests"',
    ]) {
      expect(
        policy.savedValidationFinalText(text),
        'The saved validation command succeeded. No additional tool call was executed.',
      );
    }
    expect(
      policy.savedValidationFinalText(
        'I will rewrite the file.',
        suppressedCalls: true,
      ),
      isNot(contains('rewrite')),
    );
    expect(
      policy.savedValidationFinalText('All 14 tests passed.'),
      'All 14 tests passed.',
    );
    expect(
      policy.savedValidationFinalText(
        'All 14 tests passed.',
        suppressedCalls: true,
      ),
      'All 14 tests passed.',
    );
  });

  group('ToolTerminalResponsePolicy hidden evidence delegation', () {
    final policy = _policy();

    test('preserves the extracted score matrix', () {
      expect(policy.hiddenAssistantEvidenceScore(''), 0);
      expect(policy.hiddenAssistantEvidenceScore('next task'), 1);
      expect(policy.hiddenAssistantEvidenceScore('task complete'), 2);
      expect(
        policy.hiddenAssistantEvidenceScore(
          'task complete; validation passed; saved task',
        ),
        5,
      );
      expect(
        policy.hiddenAssistantEvidenceScore('task complete but tests failed'),
        2,
      );
    });

    test('uses the delegated score for recovery acceptance', () {
      expect(policy.shouldAcceptRecoveryFinalTextResponse(''), isFalse);
      expect(
        policy.shouldAcceptRecoveryFinalTextResponse('Next task'),
        isFalse,
      );
      expect(
        policy.shouldAcceptRecoveryFinalTextResponse('Task complete'),
        isTrue,
      );
      expect(
        policy.shouldAcceptRecoveryFinalTextResponse(
          'Task complete but tests failed',
        ),
        isTrue,
      );
    });

    test('keeps terminal task-reference precedence unchanged', () {
      expect(
        policy.shouldAcceptTerminalToolRoleFinalTextResponse(
          'Task "task-1" complete.',
        ),
        isTrue,
      );
      expect(
        policy.shouldAcceptTerminalToolRoleFinalTextResponse(
          'Task "task-1" tests passed.',
        ),
        isFalse,
      );
      expect(
        policy.shouldAcceptTerminalToolRoleFinalTextResponse(
          'Task "task-1" complete. Would you like another task?',
        ),
        isFalse,
      );
    });
  });

  group('terminal inspection final text', () {
    final policy = _policy();
    final reads = [
      _result('list_directory', '{"entries":["index.html","sea.js"]}'),
      _result('read_file', '{"path":"index.html","content":"<html>"}'),
      _result('read_file', '{"path":"sea.js","content":"const WAVES = [];"}'),
    ];

    test('accepts a completed inspection review grounded in file reads', () {
      // Session 9ca277d5: the tool loop returned this review with finish=stop,
      // then Caverno discarded it and spent five minutes generating another.
      expect(
        policy.shouldAcceptTerminalInspectionFinalTextResponse(
          _inspectionReview,
          reads,
        ),
        isTrue,
      );
    });

    test('ignores think blocks when measuring visible length', () {
      expect(
        policy.shouldAcceptTerminalInspectionFinalTextResponse(
          '<think>${'x' * 500}</think>\n$_inspectionReview',
          reads,
        ),
        isTrue,
      );
    });

    test('rejects a review that is not grounded in successful reads', () {
      expect(
        policy.shouldAcceptTerminalInspectionFinalTextResponse(
          _inspectionReview,
          const [],
        ),
        isFalse,
      );
      expect(
        policy.shouldAcceptTerminalInspectionFinalTextResponse(
          _inspectionReview,
          [_result('read_file', '{"error":"permission denied"}')],
        ),
        isFalse,
      );
      expect(
        policy.shouldAcceptTerminalInspectionFinalTextResponse(
          _inspectionReview,
          [
            ...reads,
            _result('write_file', '{"path":"sea.js","created":false}'),
          ],
        ),
        isFalse,
      );
    });

    test('rejects stubs and pending inspection narration', () {
      expect(
        policy.shouldAcceptTerminalInspectionFinalTextResponse(
          'Both files look fine.',
          reads,
        ),
        isFalse,
      );
      final pendingPolicy = _policy(
        looksLikePendingToolActionResponse: (value) =>
            value.toLowerCase().contains('let me inspect'),
      );
      expect(
        pendingPolicy.shouldAcceptTerminalInspectionFinalTextResponse(
          'Let me inspect the Dart source next.\n${'Review body. ' * 40}',
          reads,
        ),
        isFalse,
      );
    });
  });

  group('background process completion claim', () {
    final policy = _policy(scanCodeUnits: true);

    test('reads an English completion claim', () {
      expect(
        policy.looksLikeBackgroundProcessCompletionClaim(
          'The release completed successfully and the build was uploaded.',
        ),
        isTrue,
      );
    });

    test('reads a CJK completion claim', () {
      // "The release completed."
      expect(
        policy.looksLikeBackgroundProcessCompletionClaim(
          '\u30ea\u30ea\u30fc\u30b9\u304c\u5b8c\u4e86\u3057\u307e'
          '\u3057\u305f\u3002',
        ),
        isTrue,
      );
    });

    test('a CJK answer denying completion is not a completion claim', () {
      // "The production release is still running. Commit and tag have not run
      // yet." The word for "completed" is a substring of "has not completed",
      // so before the CJK negative markers existed this matched as a claim and
      // cost an extra generation on every poll of a long release.
      expect(
        policy.looksLikeBackgroundProcessCompletionClaim(
          '\u672c\u756a\u30ea\u30ea\u30fc\u30b9\u51e6\u7406\u306f'
          '\u307e\u3060\u5b9f\u884c\u4e2d\u3067\u3059\u3002'
          '\u30ea\u30ea\u30fc\u30b9\u51e6\u7406\u304c\u5b8c\u4e86'
          '\u3057\u3066\u3044\u306a\u3044\u305f\u3081\u3001'
          '\u30b3\u30df\u30c3\u30c8\u3068\u30bf\u30b0\u4f5c\u6210'
          '\u306f\u307e\u3060\u5b9f\u884c\u3055\u308c\u3066'
          '\u3044\u307e\u305b\u3093\u3002',
        ),
        isFalse,
      );
    });

    test('an unrelated CJK negation does not mask a completion claim', () {
      // "The release completed. There are no items I have not checked."
      // The suppressors are the *negated completion words*, not any negation:
      // "have not checked" must leave this a claim for the monitor to check.
      expect(
        policy.looksLikeBackgroundProcessCompletionClaim(
          '\u30ea\u30ea\u30fc\u30b9\u304c\u5b8c\u4e86\u3057\u307e'
          '\u3057\u305f\u3002\u307e\u3060\u78ba\u8a8d\u3057\u3066'
          '\u3044\u306a\u3044\u9805\u76ee\u306f\u3042\u308a\u307e'
          '\u305b\u3093\u3002',
        ),
        isTrue,
      );
    });

    test('an English answer denying completion is not a completion claim', () {
      expect(
        policy.looksLikeBackgroundProcessCompletionClaim(
          'The release is still running, so the commit is not done.',
        ),
        isFalse,
      );
    });
  });
}

ToolResultInfo _result(String name, String result) =>
    ToolResultInfo(id: name, name: name, arguments: const {}, result: result);

const _inspectionReview = '''
Both files (index.html 66 lines / sea.js 333 lines) were read. This is a
Gerstner-wave plus custom-shader sea simulation. In priority order:

1. Normals mix view space and world space, so lighting distorts when the
   camera orbits. The sea mesh is unscaled, so assign the world normal.
2. The sky dome sits inside the fog range, so the gradient and sun are
   washed out. Disable fog on the sky material or enlarge the dome.
3. Foam almost never appears: the threshold is 0.85 while default wave
   height peaks near 0.5. Scale the threshold by uWaveHeight.
4. The WAVES array is nearly dead code; embedding six vec4 lines into
   one initializer is a shader compile error.

The architecture is sound. Fix 1 and 2 first; they change what you see.
''';

ToolTerminalResponsePolicy _policy({
  bool Function(String value)? looksLikePendingToolActionResponse,
  bool scanCodeUnits = false,
}) {
  return ToolTerminalResponsePolicy(
    looksLikeUnexecutedToolRequest: (_) => false,
    looksLikePlanOnlyFinalToolAnswer: (_) => false,
    looksLikePendingToolActionResponse:
        looksLikePendingToolActionResponse ?? (_) => false,
    looksLikeStructuredToolRequest: (_) => false,
    containsAnyCodeUnitSequence: scanCodeUnits
        ? CodeUnitTextScan.containsAny
        : (_, _) => false,
    containsCjkBlockerMarker: (_) => false,
    containsCjkMissingEvidenceMarker: (_) => false,
  );
}
