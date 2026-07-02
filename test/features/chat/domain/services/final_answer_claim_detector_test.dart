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

    test('prepends claim correction notices without dropping content', () {
      final content = detector.messageContentWithPrependedClaimCorrectionNotice(
        'All tests passed.',
        'A command failed, so the success claim is unverified.',
      );

      expect(content, startsWith('A command failed'));
      expect(content, contains('All tests passed.'));
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
