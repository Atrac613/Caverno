import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/final_answer_message_notice_service.dart';
import 'package:caverno/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart';

void main() {
  const service = FinalAnswerMessageNoticeService();

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
