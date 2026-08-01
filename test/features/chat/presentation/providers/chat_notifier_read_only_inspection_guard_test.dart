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
