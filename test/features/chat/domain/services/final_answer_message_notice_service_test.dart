import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/final_answer_message_notice_service.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/project_task_terminal_status.dart';
import 'package:caverno/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = FinalAnswerMessageNoticeService();

  group('project task terminal verdict', () {
    for (final prose in [
      'All work is complete.',
      '\u4f5c\u696d\u306f\u5b8c\u4e86\u3057\u307e\u3057\u305f\u3002',
      'Tout est termin\u00e9.',
    ]) {
      test('replaces unsupported readiness regardless of prose: $prose', () {
        final mutation = service.replaceUnacceptedProjectTaskCompletion(
          _assistantMessages('$prose\nPROJECT_TASK_READY_FOR_REVIEW'),
          ProjectTaskTerminalStatus(
            outcome: GoalUpdateAckOutcome.completionRejected,
            gaps: ['The verifier still failed.'],
          ),
        )!;
        expect(
          mutation.messages.last.content,
          allOf(
            contains('completion was not recorded'),
            contains('The verifier still failed.'),
            isNot(contains('PROJECT_TASK_READY_FOR_REVIEW')),
            isNot(contains(prose)),
          ),
        );
        expect(mutation.transformId, 'coding_task_completion_notice');
        expect(mutation.messages.last.id, 'assistant-1');
      });
    }
    test('preserves an accepted response', () {
      expect(
        service.replaceUnacceptedProjectTaskCompletion(
          _assistantMessages('Verified.\nPROJECT_TASK_READY_FOR_REVIEW'),
          ProjectTaskTerminalStatus(
            outcome: GoalUpdateAckOutcome.completionRecorded,
          ),
        ),
        isNull,
      );
    });
    for (final outcome in [null, GoalUpdateAckOutcome.progressLogged]) {
      test(
        'unaccepted status retains the work report without readiness: $outcome',
        () {
          final answer = service
              .replaceUnacceptedProjectTaskCompletion(
                _assistantMessages(
                  'The focused runner reported 6 passed.\nPROJECT_TASK_READY_FOR_REVIEW',
                ),
                ProjectTaskTerminalStatus(outcome: outcome),
              )!
              .messages
              .last
              .content;
          expect(answer, contains('completion was not recorded'));
          expect(answer, contains('The focused runner reported 6 passed.'));
          expect(answer, isNot(contains('PROJECT_TASK_READY_FOR_REVIEW')));
        },
      );
    }
    test('a recorded blocker replaces later completion claims', () {
      final answer = service
          .replaceUnacceptedProjectTaskCompletion(
            _assistantMessages(
              'All subtasks and verification completed.\nPROJECT_TASK_READY_FOR_REVIEW',
            ),
            ProjectTaskTerminalStatus(
              outcome: GoalUpdateAckOutcome.blockerLogged,
              gaps: ['The dry-run cannot reach the fixture API.'],
            ),
          )!
          .messages
          .last
          .content;
      expect(
        answer,
        allOf(
          contains('The dry-run cannot reach the fixture API.'),
          contains('completion was not recorded'),
          isNot(contains('All subtasks and verification completed.')),
          isNot(contains('PROJECT_TASK_READY_FOR_REVIEW')),
        ),
      );
    });
  });

  group('FinalAnswerMessageNoticeService transform IDs', () {
    test('labels an unexecuted tool request notice', () {
      final mutation = service.appendUnexecutedToolRequest(
        _assistantMessages('I will run the command `dart test`.'),
      );

      expect(mutation, isNotNull);
      expect(
        mutation!.transformId,
        UnexecutedFinalAnswerToolRequestPolicy.transformId,
      );
    });

    test('labels an unexecuted file side-effect notice', () {
      final mutation = service.appendUnexecutedFileSideEffect(
        _assistantMessages('Saved the report to report.md.'),
        [
          _toolResult('write_file', {
            'ok': false,
            'code': 'unexecuted_file_save',
            'error': 'The requested file save was not executed.',
          }),
        ],
      );

      expect(mutation, isNotNull);
      expect(
        mutation!.transformId,
        FinalAnswerMessageNoticeService.unexecutedFileSideEffectTransformId,
      );
    });

    test('labels a timed-out command claim correction', () {
      final mutation = service.replaceTimedOutCommandClaim(
        _assistantMessages('All tests passed successfully.'),
        [
          _toolResult('local_execute_command', {
            'timed_out': true,
            'error': 'Command timed out after 60 seconds.',
          }),
        ],
      );

      expect(mutation, isNotNull);
      expect(
        mutation!.transformId,
        FinalAnswerMessageNoticeService.timedOutCommandClaimTransformId,
      );
    });

    test('labels a failed command claim correction', () {
      final mutation = service.replaceFailedCommandClaim(
        _assistantMessages('The release completed successfully.'),
        [
          _toolResult('local_execute_command', {
            'exit_code': 1,
            'stderr': 'Release failed.',
          }),
        ],
      );

      expect(mutation, isNotNull);
      expect(
        mutation!.transformId,
        FinalAnswerMessageNoticeService.failedCommandClaimTransformId,
      );
    });

    test('a command refused before execution is not a failed command', () {
      final mutation = service.replaceFailedCommandClaim(
        _assistantMessages('The release completed successfully.'),
        [
          _toolResult('git_execute_command', {
            'command': 'git tag --list | head -20',
            'executed': false,
            'code': 'command_rejected_before_execution',
            'error': 'The operator "|" is not supported.',
          }),
        ],
      );

      expect(mutation, isNull);
    });

    test('a refusal neither clears nor restates an earlier failure', () {
      final mutation = service.replaceFailedCommandClaim(
        _assistantMessages('The release completed successfully.'),
        [
          _toolResult('local_execute_command', {
            'exit_code': 1,
            'stderr': 'Release failed.',
          }),
          _toolResult('git_execute_command', {
            'executed': false,
            'code': 'command_rejected_before_execution',
            'error': 'The operator "|" is not supported.',
          }),
        ],
      );

      expect(mutation, isNotNull);
      expect(mutation!.messages.last.content, contains('exit code 1'));
    });

    test('does not emit a transform when no visible message changes', () {
      final mutation = service.replaceFailedCommandClaim(
        _assistantMessages('The command still needs to be run.'),
        [
          _toolResult('local_execute_command', {
            'exit_code': 1,
            'stderr': 'Release failed.',
          }),
        ],
      );

      expect(mutation, isNull);
    });
  });
}

List<Message> _assistantMessages(String content) => [
  Message(
    id: 'assistant-1',
    role: MessageRole.assistant,
    content: content,
    timestamp: DateTime(2026, 8, 9),
  ),
];

ToolResultInfo _toolResult(String name, Map<String, dynamic> result) =>
    ToolResultInfo(
      id: '$name-result',
      name: name,
      arguments: const {},
      result: jsonEncode(result),
    );
