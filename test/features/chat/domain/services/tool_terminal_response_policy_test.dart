import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_terminal_response_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}) {
  return ToolTerminalResponsePolicy(
    looksLikeUnexecutedToolRequest: (_) => false,
    looksLikePlanOnlyFinalToolAnswer: (_) => false,
    looksLikePendingToolActionResponse:
        looksLikePendingToolActionResponse ?? (_) => false,
    looksLikeStructuredToolRequest: (_) => false,
    containsAnyCodeUnitSequence: (_, _) => false,
    containsCjkBlockerMarker: (_) => false,
    containsCjkMissingEvidenceMarker: (_) => false,
  );
}
