import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_detector.dart';

ToolResultInfo _result(String name, String result) =>
    ToolResultInfo(id: 't', name: name, arguments: const {}, result: result);

const _repoClaim = 'I checked the repository: the latest commit is c7d4341.';

void main() {
  const detector = FinalAnswerClaimDetector();

  group('unverified read-only inspection guard characterization', () {
    test('does NOT fire when a project-state claim is backed by a successful '
        'local_execute_command (e.g. flutter analyze)', () {
      final fired = detector.buildUnverifiedReadOnlyInspectionClaimToolResult(
        candidateResponse:
            'I ran flutter analyze on the project: no issues found.',
        toolResults: [
          _result(
            'local_execute_command',
            '{"exit_code":0,"stdout":"No issues found!"}',
          ),
        ],
      );
      expect(fired, isNull);
    });

    test('does NOT fire when a project-state claim is backed by a successful '
        'process_wait (commands run in the background via process_start)', () {
      // Real-world "fvm flutter clean/pub get/analyze" runs go through
      // process_start + process_wait. A completed process result is only
      // "successful" when it carries ok=true, status=exited AND exit_code 0
      // (see ToolCallExecutionPolicy.toolResultHasSuccessfulExit) — mirror
      // that exact shape so this path counts as inspection verification.
      final fired = detector.buildUnverifiedReadOnlyInspectionClaimToolResult(
        candidateResponse:
            'fvm flutter analyze finished for the project: no issues found.',
        toolResults: [
          _result(
            'process_wait',
            '{"ok":true,"status":"exited","exit_code":0,'
                '"stdout_tail":"No issues found!"}',
          ),
        ],
      );
      expect(fired, isNull);
    });

    test('does NOT fire when backed by a successful read_file', () {
      final fired = detector.buildUnverifiedReadOnlyInspectionClaimToolResult(
        candidateResponse: 'I read the pubspec file; it exists.',
        toolResults: [_result('read_file', '{"content":"name: caverno"}')],
      );
      expect(fired, isNull);
    });

    test('fires (true positive) when an inspection claim has no backing tool '
        'result at all', () {
      final fired = detector.buildUnverifiedReadOnlyInspectionClaimToolResult(
        candidateResponse: _repoClaim,
        toolResults: const [],
      );
      expect(fired, isNotNull);
    });

    test('does NOT fire on a web-sourced answer that names no local path '
        '(regression: session 165f1371 gen-7)', () {
      // The answer below is correct and fully tool-backed -- search_web plus
      // http_get against the OpenAI docs -- but it was erased by this guard.
      // The only target marker it carried was the backtick around a code span,
      // and the completed marker was 「確認しました」; the negative guard missed
      // because the sentence negates with 「含まれていませんでした」.
      const answer =
          '検索結果とOpenAI公式モデルページを確認しましたが、取得できた内容には '
          'GPT-5.6 Luna のデフォルトの `reasoning_effort` の具体的な値が'
          '含まれていませんでした。';

      final fired = detector.buildUnverifiedReadOnlyInspectionClaimToolResult(
        candidateResponse: answer,
        toolResults: [
          _result('search_web', '{"ok":true,"results":[]}'),
          _result('http_get', '{"ok":true,"status":200,"body":"..."}'),
        ],
      );

      expect(fired, isNull);
    });

    test('still fires when a web turn also makes a local file claim', () {
      // The web exemption is about the domain of the claim, not about the
      // presence of a web tool: naming a project file is still a claim about
      // this machine, and no inspection result backs it here.
      final fired = detector.buildUnverifiedReadOnlyInspectionClaimToolResult(
        candidateResponse:
            'I checked lib/main.dart against the docs; the file exists.',
        toolResults: [_result('search_web', '{"ok":true,"results":[]}')],
      );

      expect(fired, isNotNull);
    });

    test('a backtick alone is not a local target marker', () {
      expect(
        detector.looksLikeCompletedReadOnlyInspectionClaim(
          'I checked and confirmed the `reasoning_effort` value.',
        ),
        isFalse,
      );
    });

    test('mentionsLocalFilesystemPath ignores URLs but sees real paths', () {
      expect(
        detector.mentionsLocalFilesystemPath(
          'See https://developers.openai.com/api/docs/models for details.',
        ),
        isFalse,
      );
      expect(detector.mentionsLocalFilesystemPath('lib/main.dart'), isTrue);
      expect(
        detector.mentionsLocalFilesystemPath('~/.caverno/app_logs'),
        isTrue,
      );
      expect(detector.mentionsLocalFilesystemPath('pubspec.yaml'), isTrue);
    });

    test('the notice is appended, never replacing the answer', () {
      const answer = 'I checked the repository: the latest commit is c7d4341.';

      final withNotice = detector
          .messageContentWithUnverifiedReadOnlyInspectionNotice(answer);

      expect(
        withNotice,
        startsWith(answer),
        reason: 'a misfire must cost a paragraph, not the whole answer',
      );
      expect(
        withNotice,
        contains(FinalAnswerClaimDetector.unverifiedReadOnlyInspectionNotice),
      );
    });

    test('does NOT fire when a repo-state claim is backed by a successful '
        'git_execute_command (regression: the git false positive)', () {
      final gitResult = _result(
        'git_execute_command',
        '{"exit_code":0,"stdout":"c7d4341 chore: bump version"}',
      );

      // A successful git_execute_command now counts as a read-only inspection
      // result, in line with the canonical command-tool set. (Before the fix
      // this returned false and the guard fired on a genuine git inspection.)
      expect(
        detector.hasSuccessfulReadOnlyInspectionResult([gitResult]),
        isTrue,
        reason: 'git_execute_command is recognized as a command execution',
      );
      // The claim half of the trigger is still satisfied for a repo summary,
      // so this proves the fix is on the verification side, not the wording.
      expect(
        detector.looksLikeCompletedReadOnlyInspectionClaim(_repoClaim),
        isTrue,
      );
      final fired = detector.buildUnverifiedReadOnlyInspectionClaimToolResult(
        candidateResponse: _repoClaim,
        toolResults: [gitResult],
      );
      expect(
        fired,
        isNull,
        reason: 'git-backed inspection must not be flagged unverified',
      );
    });
  });
}
