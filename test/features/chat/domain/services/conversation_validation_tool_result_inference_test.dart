import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_validation_tool_result_inference.dart';

void main() {
  test('infers failed validation from tool exit codes', () {
    final result = ConversationValidationToolResultInference.infer(
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Run validation',
        validationCommand: 'flutter test',
      ),
      toolResults: const [
        ConversationValidationToolResultInput(
          toolName: 'local_execute_command',
          rawResult:
              '{"command":"flutter test","exit_code":1,"stdout":"1 test found.","stderr":"1 smoke test failed."}',
        ),
      ],
    );

    expect(result, isNotNull);
    expect(result!.status, ConversationWorkflowTaskStatus.blocked);
    expect(
      result.validationStatus,
      ConversationExecutionValidationStatus.failed,
    );
    expect(result.summary, 'Validation failed while running flutter test.');
    expect(result.blockedReason, contains('1 smoke test failed.'));
    expect(result.validationCommand, 'flutter test');
    expect(result.validationSummary, contains('1 smoke test failed.'));
  });

  test('infers passed validation from successful tool output', () {
    final result = ConversationValidationToolResultInference.infer(
      task: const ConversationWorkflowTask(
        id: 'task-2',
        title: 'Review validation',
        status: ConversationWorkflowTaskStatus.completed,
        validationCommand: 'git diff --check',
      ),
      toolResults: const [
        ConversationValidationToolResultInput(
          toolName: 'git_execute_command',
          rawResult:
              '{"command":"git diff --check","exit_code":0,"stdout":"No issues found.","stderr":""}',
        ),
      ],
    );

    expect(result, isNotNull);
    expect(result!.status, ConversationWorkflowTaskStatus.completed);
    expect(
      result.validationStatus,
      ConversationExecutionValidationStatus.passed,
    );
    expect(result.summary, 'Validation passed while running git diff --check.');
    expect(result.validationSummary, contains('No issues found.'));
  });

  test('returns null when no validation command tools were executed', () {
    final result = ConversationValidationToolResultInference.infer(
      task: const ConversationWorkflowTask(
        id: 'task-3',
        title: 'Ignore unrelated tools',
      ),
      toolResults: const [
        ConversationValidationToolResultInput(
          toolName: 'read_file',
          rawResult: '{"path":"README.md","content":"# Example"}',
        ),
      ],
    );

    expect(result, isNull);
  });

  test('infers passed validation from a successful ping result', () {
    final result = ConversationValidationToolResultInference.infer(
      task: const ConversationWorkflowTask(
        id: 'task-4',
        title: 'Check host reachability',
      ),
      toolResults: const [
        ConversationValidationToolResultInput(
          toolName: 'ping',
          rawResult:
              '{"host":"example.com","resolved_ip":"93.184.216.34","results":[{"seq":1,"ttl":55,"time_ms":12.3}],"summary":{"transmitted":1,"received":1,"loss_percent":0.0}}',
        ),
      ],
    );

    expect(result, isNotNull);
    expect(result!.status, ConversationWorkflowTaskStatus.inProgress);
    expect(
      result.validationStatus,
      ConversationExecutionValidationStatus.passed,
    );
    expect(result.validationCommand, 'ping example.com');
    expect(result.validationSummary, contains('Received 1 of 1 ping response'));
  });

  test('infers failed validation from an HTTP status error', () {
    final result = ConversationValidationToolResultInference.infer(
      task: const ConversationWorkflowTask(
        id: 'task-5',
        title: 'Check health endpoint',
      ),
      toolResults: const [
        ConversationValidationToolResultInput(
          toolName: 'http_status',
          rawResult:
              '{"url":"https://example.com/health","status_code":503,"reason_phrase":"Service Unavailable","response_time_ms":48}',
        ),
      ],
    );

    expect(result, isNotNull);
    expect(result!.status, ConversationWorkflowTaskStatus.blocked);
    expect(
      result.validationStatus,
      ConversationExecutionValidationStatus.failed,
    );
    expect(result.validationCommand, 'GET https://example.com/health');
    expect(result.blockedReason, contains('HTTP 503 Service Unavailable'));
  });

  test('infers SSH validation results from formatted command output', () {
    final result = ConversationValidationToolResultInference.infer(
      task: const ConversationWorkflowTask(
        id: 'task-6',
        title: 'Run remote validation',
      ),
      toolResults: const [
        ConversationValidationToolResultInput(
          toolName: 'ssh_execute_command',
          rawResult: 'exit_code: 0\n--- stdout ---\nremote validation passed\n',
        ),
      ],
    );

    expect(result, isNotNull);
    expect(result!.status, ConversationWorkflowTaskStatus.inProgress);
    expect(
      result.validationStatus,
      ConversationExecutionValidationStatus.passed,
    );
    expect(result.validationSummary, contains('remote validation passed'));
  });
}
