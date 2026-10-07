import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_edit_format_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (var mask = 0; mask < 8; mask++) {
    test(
      'scores each format combination and preference for mask $mask',
      () async {
        final supported = [for (var i = 0; i < 3; i++) mask & (1 << i) != 0];
        final harness = _Harness(
          responses: [
            for (var i = 0; i < 3; i++)
              supported[i] ? _outputs[i] : 'not an edit',
          ],
        );
        final result = await harness.run();
        final count = supported.where((value) => value).length;
        final preference = supported[2]
            ? 'unifiedDiff'
            : supported[1]
            ? 'searchReplace'
            : supported[0]
            ? 'wholeFile'
            : 'unknown';
        expect(harness.requests, hasLength(3));
        expect(result.id, 'edit_format_fidelity');
        expect(
          result.status,
          count == 3
              ? LiveLlmDiagnosticStatus.passed
              : count == 0
              ? LiveLlmDiagnosticStatus.failed
              : LiveLlmDiagnosticStatus.warning,
        );
        expect(result.metadata, {'editFormatPreference': preference});
        expect(
          result.summary,
          count == 0
              ? 'The model did not reproduce any supported edit format exactly.'
              : 'The model reliably produced $preference edits.',
        );
        expect(result.passedChecks, count);
        expect(result.totalChecks, 3);
        expect(result.elapsed, Duration.zero);
        expect(result.usage.toJson(), {
          'promptTokens': 30,
          'completionTokens': 9,
          'totalTokens': 39,
        });
        for (var i = 0; i < 3; i++) {
          expect(
            result.details,
            contains('${_labels[i]}: ${supported[i] ? 'passed' : 'failed'}'),
          );
        }
        if (count == 3) {
          expect(
            result.details,
            'wholeFile: passed\nsearchReplace: passed\nunifiedDiff: passed',
          );
        }
      },
    );
  }

  test('preserves request order and exact instructions', () async {
    final harness = _Harness();
    await harness.run();
    for (var i = 0; i < 3; i++) {
      expect(harness.requests[i].single.role, MessageRole.user);
      expect(
        harness.requests[i].single.content,
        'Update the greeting from Hello to Welcome without changing any '
        'other text. The current lib/greeting.dart contents are:\n\n'
        '$_original\n\n${_instructions[i]}',
      );
    }
  });

  test(
    'scores visible single-fenced edits while preserving raw reasoning',
    () async {
      final harness = _Harness(
        responses: [
          for (final content in _outputs)
            '<think>edit reasoning</think>```dart\n$content\n```',
        ],
      );
      final result = await harness.run();
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(result.modelContent, contains('<think>edit reasoning</think>'));
      expect(result.modelContent, contains('```dart'));
    },
  );

  test('accepts unified headers without a and b prefixes', () async {
    final result = await _Harness(
      responses: [
        _whole,
        _search,
        _diff.replaceFirst('--- a/', '--- ').replaceFirst('+++ b/', '+++ '),
      ],
    ).run();
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.metadata['editFormatPreference'], 'unifiedDiff');
  });

  test(
    'does not forgive a changed hunk when file headers are normalized',
    () async {
      final result = await _Harness(
        responses: [
          _whole,
          _search,
          _diff
              .replaceFirst('--- a/', '--- ')
              .replaceFirst('@@ -1,4 +1,4 @@', '@@ -1,3 +1,3 @@'),
        ],
      ).run();
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.metadata['editFormatPreference'], 'searchReplace');
      expect(result.details, contains('unifiedDiff: failed'));
    },
  );

  test('names truncation only when the visible edit mismatches', () async {
    final result = await _Harness(
      responses: [_whole, _search, ''],
      finishReason: 'length',
    ).run();
    expect(result.status, LiveLlmDiagnosticStatus.warning);
    expect(
      result.details,
      contains('response hit the token cap (finish_reason: length)'),
    );
    expect(
      result.details,
      startsWith('wholeFile: passed\nsearchReplace: passed\n'),
    );
  });

  test('a complete edit still passes when finish reason says length', () async {
    final result = await _Harness(finishReason: 'length').run();
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.details, isNot(contains('token cap')));
  });

  test(
    'reports the first mismatched line with the original expected text',
    () async {
      final result = await _Harness(
        responses: [_whole.replaceFirst('Welcome', 'Hello'), _search, _diff],
      ).run();
      expect(result.details, contains('wholeFile: failed'));
      expect(result.details, contains('line 3'));
      expect(result.details, contains('Welcome'));
      expect(result.details, contains('Hello'));
    },
  );

  test('bounds raw previews separately for each format', () async {
    final content = List.filled(500, 'x').join();
    final result = await _Harness(responses: [content, content, content]).run();
    expect(
      result.modelContent,
      [
        for (final label in _labels)
          '$label: ${List.filled(360, 'x').join()}...',
      ].join('\n\n'),
    );
  });

  for (final arm in [1, 2, 3]) {
    test('propagates arm $arm exceptions without later requests', () async {
      final failure = StateError('arm $arm');
      final harness = _Harness(failingArm: arm, failure: failure);
      await expectLater(harness.run(), throwsA(same(failure)));
      expect(harness.requests, hasLength(arm));
    });
  }
}

const _original = r'''String buildLabel(String name) {
  final trimmed = name.trim();
  return 'Hello, $trimmed!';
}''';
const _whole = r'''String buildLabel(String name) {
  final trimmed = name.trim();
  return 'Welcome, $trimmed!';
}''';
const _search = r'''<<<<<<< SEARCH
  return 'Hello, $trimmed!';
=======
  return 'Welcome, $trimmed!';
>>>>>>> REPLACE''';
const _diff = r'''--- a/lib/greeting.dart
+++ b/lib/greeting.dart
@@ -1,4 +1,4 @@
 String buildLabel(String name) {
   final trimmed = name.trim();
-  return 'Hello, $trimmed!';
+  return 'Welcome, $trimmed!';
 }''';
const _outputs = [_whole, _search, _diff];
const _labels = ['wholeFile', 'searchReplace', 'unifiedDiff'];
const _instructions = [
  'Return the complete updated file contents with no markdown fence.',
  'Return one exact SEARCH/REPLACE block using the markers '
      '<<<<<<< SEARCH, =======, and >>>>>>> REPLACE. Include only the '
      'changed line in each side and no markdown fence.',
  'Return one syntactically valid unified diff that can be applied '
      'to lib/greeting.dart. Include every available unchanged line as '
      'context, and ensure each hunk header count matches the old and '
      'new lines in that hunk. Return no markdown fence or explanation.',
];

class _Harness {
  _Harness({
    this.responses = _outputs,
    this.finishReason = 'stop',
    this.failingArm,
    this.failure,
  });
  final List<String> responses;
  final String finishReason;
  final int? failingArm;
  final Object? failure;
  final requests = <List<Message>>[];

  Future<LiveLlmDiagnosticProbeResult> run() => LiveLlmEditFormatProbe(
    complete: ({required messages}) async {
      requests.add(messages);
      if (requests.length == failingArm) throw failure!;
      return ChatCompletionResult(
        content: responses[requests.length - 1],
        finishReason: finishReason,
        usage: const TokenUsage(
          promptTokens: 10,
          completionTokens: 3,
          totalTokens: 13,
        ),
      );
    },
    messages: (user) => [
      Message(
        id: 'fixture',
        role: MessageRole.user,
        content: user,
        timestamp: DateTime.utc(2026, 10, 8),
      ),
    ],
  ).run();
}
