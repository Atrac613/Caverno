import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';
import 'package:test/test.dart';

void main() {
  const service = CodingCommandOutputGuardrailService();
  const outputDetector = CodingCommandOutputIssueDetector();
  const preflightDetector = CodingCommandPreflightIssueDetector();

  group('CodingCommandOutputGuardrailService compatibility facade', () {
    test('preserves the live replay classification and payload fields', () {
      final fixture = _loadReplayFixture(
        'coding_zero_exit_artifact_error_replay.json',
      );
      final feedback = service.buildFeedbackToolResult(
        toolResults: fixture.toolResults,
        now: DateTime.fromMicrosecondsSinceEpoch(42),
      );

      expect(feedback, isNotNull);
      expect(feedback!.id, 'coding_output_feedback_42');
      expect(feedback.name, fixture.expectedFeedbackToolName);

      final payload = jsonDecode(feedback.result) as Map<String, dynamic>;
      expect(payload['schema'], CodingCommandOutputGuardrailService.schemaName);
      expect(payload['provider'], 'command_output_guardrail');
      expect(payload['success'], isFalse);
      expect(payload['validation_status'], fixture.expectedValidationStatus);
      final issues = payload['issues'] as List<dynamic>;
      expect(issues, hasLength(1));
      expect(issues.single, containsPair('command', fixture.expectedCommand));
      expect(issues.single, containsPair('source', 'stdout'));
      expect(
        issues.single,
        containsPair('summary', fixture.expectedIssueSummary),
      );
    });

    test('keeps feedback JSON byte-compatible', () {
      final result = _commandResult(
        id: 'call-1',
        command: 'python3 get_weather.py',
        workingDirectory: '/tmp/weather',
        stdout: '# Error\nrequired artifact is missing',
      );
      final feedback = service.buildFeedbackToolResult(
        toolResults: [result],
        now: DateTime.fromMicrosecondsSinceEpoch(7),
      );
      final issue = {
        'tool_name': 'local_execute_command',
        'command': 'python3 get_weather.py',
        'working_directory': '/tmp/weather',
        'exit_code': 0,
        'source': 'stdout',
        'summary': 'Output contains a Markdown error heading.',
        'excerpt': '# Error\nrequired artifact is missing',
      };
      final expectedPayload = {
        'schema': 'caverno_coding_output_feedback',
        'provider': 'command_output_guardrail',
        'success': false,
        'validation_status': 'failed',
        'error':
            'A command exited with code 0, but its command shape or output '
            'reports a failed generated artifact or missing required data.',
        'instruction':
            'Treat the coding task as incomplete. Inspect and repair the script, generated file, or data lookup, then rerun the relevant command before claiming completion.',
        'issues': [issue],
        'diagnostics': [
          {
            'severity': 'Error',
            'code': 'command_output_failure',
            'message':
                'Output contains a Markdown error heading. '
                '# Error\nrequired artifact is missing',
          },
        ],
      };

      expect(feedback!.id, 'coding_output_feedback_7');
      expect(feedback.name, 'coding_output_feedback');
      expect(feedback.arguments, {
        'issue_count': 1,
        'commands': ['python3 get_weather.py'],
      });
      expect(feedback.result, jsonEncode(expectedPayload));
    });

    test('preserves issue ordering and caps feedback at three issues', () {
      final results = [
        for (var index = 1; index <= 4; index += 1)
          _commandResult(
            id: 'call-$index',
            command: 'command-$index',
            workingDirectory: '/tmp',
            stdout: 'No data found for command $index.',
          ),
      ];

      final feedback = service.buildFeedbackToolResult(
        toolResults: results,
        now: DateTime.fromMicrosecondsSinceEpoch(9),
      );
      final payload = jsonDecode(feedback!.result) as Map<String, dynamic>;
      final issues = payload['issues'] as List<dynamic>;

      expect(feedback.arguments['issue_count'], 3);
      expect(feedback.arguments['commands'], [
        'command-1',
        'command-2',
        'command-3',
      ]);
      expect(
        issues
            .map((issue) => (issue as Map<String, dynamic>)['command'])
            .toList(),
        ['command-1', 'command-2', 'command-3'],
      );
    });

    test('suppresses recursive feedback and clean result batches', () {
      final existingFeedback = ToolResultInfo(
        id: 'feedback',
        name: CodingCommandOutputGuardrailService.toolName,
        arguments: const {},
        result: '{}',
      );
      final clean = _commandResult(
        id: 'clean',
        command: 'dart test',
        workingDirectory: '/workspace',
        stdout: 'All tests passed.',
      );

      expect(
        service.buildFeedbackToolResult(toolResults: [existingFeedback, clean]),
        isNull,
      );
      expect(service.buildFeedbackToolResult(toolResults: [clean]), isNull);
      expect(service.buildFeedbackToolResult(toolResults: const []), isNull);
    });

    test('delegates output APIs without changing results', () {
      final result = _commandResult(
        id: 'issue',
        command: 'python3 app.py',
        workingDirectory: '/workspace',
        stdout: 'No data found.',
      );
      final decoded = jsonDecode(result.result) as Map<String, dynamic>;

      expect(
        CodingCommandOutputGuardrailService.detectIssue(result)?.toJson(),
        outputDetector.detect(result)?.toJson(),
      );
      expect(
        CodingCommandOutputGuardrailService.detectIssueFromDecodedCommandResult(
          toolName: result.name,
          decoded: decoded,
        )?.toJson(),
        outputDetector
            .detectFromDecodedCommandResult(
              toolName: result.name,
              decoded: decoded,
            )
            ?.toJson(),
      );
      expect(
        CodingCommandOutputGuardrailService.commandResultReportsOutputIssue(
          result.result,
        ),
        outputDetector.commandResultReportsOutputIssue(result.result),
      );
    });

    test('delegates preflight APIs without changing results', () {
      const malformed = 'dart create --force . sample';
      const masked = r'first && second; test $? -ne 0';

      expect(
        CodingCommandOutputGuardrailService.detectPreflightIssue(
          toolName: 'local_execute_command',
          command: malformed,
          workingDirectory: '/tmp',
        )?.toJson(),
        preflightDetector
            .detect(
              toolName: 'local_execute_command',
              command: malformed,
              workingDirectory: '/tmp',
            )
            ?.toJson(),
      );
      expect(
        CodingCommandOutputGuardrailService.detectMaskedExitStatusIssue(
          command: masked,
          workingDirectory: '/tmp',
        )?.toJson(),
        preflightDetector
            .detectMaskedExitStatusIssue(
              command: masked,
              workingDirectory: '/tmp',
            )
            ?.toJson(),
      );
    });

    test('builds the exact preflight tool result and null passthrough', () {
      const command = 'dart create --force . sample';
      final result = CodingCommandOutputGuardrailService.buildPreflightResult(
        toolName: 'local_execute_command',
        command: command,
        workingDirectory: '/tmp/project',
      )!;

      expect(result.toolName, 'local_execute_command');
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Dart create command specifies multiple target directories.',
      );
      expect(jsonDecode(result.result), {
        'ok': false,
        'code': 'dart_create_multiple_targets',
        'command': command,
        'working_directory': '/tmp/project',
        'segment': command,
        'summary': 'Dart create command specifies multiple target directories.',
        'instruction':
            'Run dart create with exactly one target directory. Use '
            '"dart create --force prime_numbers_pkg" from the parent '
            'directory, or create the directory first and run '
            '"dart create --force ." inside it.',
        'targets': ['.', 'sample'],
        'required_action':
            'Run dart create with exactly one target directory. Use '
            '"dart create --force prime_numbers_pkg" from the parent '
            'directory, or create the directory first and run '
            '"dart create --force ." inside it.',
      });
      expect(
        CodingCommandOutputGuardrailService.buildPreflightResult(
          toolName: 'read_file',
          command: command,
          workingDirectory: '/tmp/project',
        ),
        isNull,
      );
      expect(
        CodingCommandOutputGuardrailService.buildPreflightResult(
          toolName: 'process_start',
          command: '',
          workingDirectory: '/tmp/project',
        ),
        isNull,
      );
    });

    test('delegates stable feedback signatures', () {
      final feedback = service.buildFeedbackToolResult(
        toolResults: [
          _commandResult(
            id: 'issue',
            command: 'python3 app.py',
            workingDirectory: '/workspace',
            stdout: 'No data found.',
          ),
        ],
        now: DateTime.fromMicrosecondsSinceEpoch(12),
      )!;

      expect(
        CodingCommandOutputGuardrailService.feedbackSignature(feedback),
        outputDetector.feedbackSignature(
          feedback,
          feedbackToolName: CodingCommandOutputGuardrailService.toolName,
        ),
      );
    });
  });
}

ToolResultInfo _commandResult({
  required String id,
  required String command,
  required String workingDirectory,
  required String stdout,
  String stderr = '',
}) {
  return ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: {'command': command, 'working_directory': workingDirectory},
    result: jsonEncode({
      'command': command,
      'working_directory': workingDirectory,
      'exit_code': 0,
      'stdout': stdout,
      'stderr': stderr,
    }),
  );
}

_ReplayFixture _loadReplayFixture(String fixtureName) {
  final fixture =
      jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
          as Map<String, dynamic>;
  final expected = fixture['expected'] as Map<String, dynamic>;
  return _ReplayFixture(
    toolResults: (fixture['toolResults'] as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => ToolResultInfo(
            id: item['id'] as String,
            name: item['name'] as String,
            arguments: item['arguments'] as Map<String, dynamic>,
            result: item['result'] as String,
          ),
        )
        .toList(growable: false),
    expectedCommand: expected['command'] as String,
    expectedFeedbackToolName: expected['feedbackToolName'] as String,
    expectedValidationStatus: expected['validationStatus'] as String,
    expectedIssueSummary: expected['issueSummary'] as String,
  );
}

class _ReplayFixture {
  const _ReplayFixture({
    required this.toolResults,
    required this.expectedCommand,
    required this.expectedFeedbackToolName,
    required this.expectedValidationStatus,
    required this.expectedIssueSummary,
  });

  final List<ToolResultInfo> toolResults;
  final String expectedCommand;
  final String expectedFeedbackToolName;
  final String expectedValidationStatus;
  final String expectedIssueSummary;
}
