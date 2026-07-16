import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_detector.dart';

void main() {
  const detector = FinalAnswerClaimDetector();

  group('FinalAnswerClaimDetector', () {
    test('builds an unexecuted command action result for unsupported claims', () {
      final result = detector.buildUnexecutedCommandActionToolResult(
        candidateResponse:
            'The flutter build completed successfully and the IPA was uploaded.',
        toolResults: const [],
      );

      expect(result, isNotNull);
      expect(result!.name, 'local_execute_command');
      final decoded = jsonDecode(result.result) as Map<String, dynamic>;
      expect(decoded['code'], 'unexecuted_command_action');
      expect(decoded['claimedResponse'], contains('flutter build completed'));
    });

    test(
      'does not block completed command claims with successful evidence',
      () {
        final result = detector.buildUnexecutedCommandActionToolResult(
          candidateResponse: 'flutter analyze completed successfully.',
          toolResults: [
            _result(
              'local_execute_command',
              '{"exit_code":0,"stdout":"No issues found!"}',
            ),
          ],
        );

        expect(result, isNull);
      },
    );

    test(
      'does not flag read-only claims backed by successful git commands',
      () {
        final result = detector
            .buildUnverifiedReadOnlyInspectionClaimToolResult(
              candidateResponse:
                  'I checked the repository: the latest commit is c7d4341.',
              toolResults: [
                _result(
                  'git_execute_command',
                  '{"exit_code":0,"stdout":"c7d4341 chore: bump version"}',
                ),
              ],
            );

        expect(
          detector.looksLikeCompletedReadOnlyInspectionClaim(
            'I checked the repository: the latest commit is c7d4341.',
          ),
          isTrue,
        );
        expect(result, isNull);
      },
    );

    test('builds browser action results from recovered snapshots', () {
      final result = detector.buildUnexecutedSkippedBrowserActionToolResult(
        candidateResponse: 'I clicked the button.',
        batchToolResults: [
          _result(
            'browser_snapshot',
            '{"ok":true}',
            id: 'recovered_browser_snapshot_1',
          ),
        ],
        latestUserContent: 'Click the submit button',
      );

      expect(result, isNotNull);
      expect(result!.name, 'browser_click');
      expect(
        jsonDecode(result.result),
        containsPair('code', 'unexecuted_browser_action'),
      );
    });

    test('builds file side-effect results and claim notices', () {
      final unexecuted = detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse: 'Saved the report to report.md.',
        toolResults: const [],
        latestUserContent: 'Save this as a Markdown file',
      );

      expect(unexecuted, isNotNull);
      expect(
        jsonDecode(unexecuted!.result),
        containsPair('code', 'unexecuted_file_save'),
      );
      expect(
        detector.looksLikeUnsupportedFileSideEffectClaim(
          'Saved the report to report.md.',
          toolResults: [unexecuted],
        ),
        isTrue,
      );

      final withNotice = detector
          .messageContentWithUnexecutedCommandActionNotice(
            'The release script completed successfully.',
          );
      expect(
        withNotice,
        FinalAnswerClaimDetector.unexecutedCommandActionNotice,
      );
    });

    test('accepts runtime state persistence backed by a successful command', () {
      final unexecuted = detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse:
            'Runtime state was saved to `.todo.json` and reloaded across processes.',
        toolResults: [
          _result(
            'local_execute_command',
            '{"exit_code":0,"stdout":"Added task 1"}',
          ),
        ],
        latestUserContent: 'Implement a persistent command-line TODO app.',
      );

      expect(unexecuted, isNull);
    });

    test(
      'accepts CJK runtime state persistence backed by a successful command',
      () {
        final stateSaved = String.fromCharCodes(const [
          0x72b6,
          0x614b,
          0x3092,
          0x4fdd,
          0x5b58,
        ]);
        final unexecuted = detector.buildUnexecutedFileSideEffectToolResult(
          candidateResponse: '$stateSaved (`.todo.json`).',
          toolResults: [
            _result(
              'local_execute_command',
              '{"exit_code":0,"stdout":"Added task 1"}',
            ),
          ],
          latestUserContent: 'Implement a persistent command-line TODO app.',
        );

        expect(unexecuted, isNull);
      },
    );

    test('does not treat unrelated command success as a report file save', () {
      final unexecuted = detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse: 'Saved the report to report.json.',
        toolResults: [
          _result(
            'local_execute_command',
            '{"exit_code":0,"stdout":"No issues found"}',
          ),
        ],
        latestUserContent: 'Save the report as a JSON file.',
      );

      expect(unexecuted, isNotNull);
      expect(
        jsonDecode(unexecuted!.result),
        containsPair('code', 'unexecuted_file_save'),
      );
    });

    test(
      'does not invent a file save for existing implementation validation',
      () {
        final unexecuted = detector.buildUnexecutedFileSideEffectToolResult(
          candidateResponse:
              'bin/todo.dart is already implemented. Running acceptance validation.',
          toolResults: const [],
          latestUserContent: 'Create a Dart TODO application.',
        );

        expect(unexecuted, isNull);
      },
    );

    test('retains a missing future file mutation action', () {
      final unexecuted = detector.buildUnexecutedFileSideEffectToolResult(
        candidateResponse: 'I will create the requested Markdown file now.',
        toolResults: const [],
        latestUserContent: 'Save this as a Markdown file.',
      );

      expect(unexecuted, isNotNull);
      expect(
        jsonDecode(unexecuted!.result),
        containsPair('code', 'unexecuted_file_save'),
      );
    });

    test('prepends claim correction notices without dropping content', () {
      final content = detector.messageContentWithPrependedClaimCorrectionNotice(
        'All tests passed.',
        'A command failed, so the success claim is unverified.',
      );

      expect(content, startsWith('A command failed'));
      expect(content, contains('All tests passed.'));
    });

    test('recognizes Japanese command verification promises', () {
      final verifyPromise = String.fromCharCodes(const [
        0x6b8b,
        0x308a,
        0x306e,
        0x53d7,
        0x3051,
        0x5165,
        0x308c,
        0x57fa,
        0x6e96,
        0x3092,
        0x30b3,
        0x30de,
        0x30f3,
        0x30c9,
        0x3067,
        0x691c,
        0x8a3c,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      final inspectPromise = String.fromCharCodes(const [
        0x4e0d,
        0x660e,
        0x306a,
        0x49,
        0x44,
        0x306e,
        0x52d5,
        0x4f5c,
        0x3092,
        0x30ed,
        0x30fc,
        0x30ab,
        0x30eb,
        0x30b3,
        0x30de,
        0x30f3,
        0x30c9,
        0x3067,
        0x78ba,
        0x8a8d,
        0x3057,
        0x307e,
        0x3059,
        0x3002,
      ]);
      expect(
        detector.looksLikeFutureCommandExecutionAction(verifyPromise),
        isTrue,
      );
      expect(
        detector.looksLikeFutureCommandExecutionAction(inspectPromise),
        isTrue,
      );
    });
  });
}

ToolResultInfo _result(String name, String result, {String? id}) {
  return ToolResultInfo(
    id: id ?? 'result-$name',
    name: name,
    arguments: const {},
    result: result,
  );
}
