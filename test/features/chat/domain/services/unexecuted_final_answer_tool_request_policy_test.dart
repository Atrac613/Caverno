import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_exit_reason.dart';
import 'package:caverno/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart';
import 'package:test/test.dart';

const _policy = UnexecutedFinalAnswerToolRequestPolicy();

String _toolCall(
  String name, {
  Map<String, dynamic> arguments = const {'path': 'lib/main.dart'},
  String tag = 'tool_call',
}) {
  return '<$tag>${jsonEncode({'name': name, 'arguments': arguments})}</$tag>';
}

ToolResultInfo _existingResult({
  String id = 'existing',
  String name = 'write_file',
  Map<String, dynamic> arguments = const {},
  String result = '{"ok":true}',
}) {
  return ToolResultInfo(
    id: id,
    name: name,
    arguments: arguments,
    result: result,
  );
}

UnexecutedFinalAnswerToolRequestInput _input({
  required String content,
  List<ToolResultInfo> existingToolResults = const [],
  bool hasTimedOutCommandResult = false,
  bool hasFailedCommandValidation = false,
  bool hasUnexecutedCommandActionResult = false,
  bool hasUnexecutedFileSideEffectResult = false,
  bool hasSuccessfulFileMutationEvidence = false,
  bool hasSuccessfulCommandExecutionEvidence = false,
}) {
  return UnexecutedFinalAnswerToolRequestInput(
    content: content,
    existingToolResults: existingToolResults,
    hasTimedOutCommandResult: hasTimedOutCommandResult,
    hasFailedCommandValidation: hasFailedCommandValidation,
    hasUnexecutedCommandActionResult: hasUnexecutedCommandActionResult,
    hasUnexecutedFileSideEffectResult: hasUnexecutedFileSideEffectResult,
    hasSuccessfulFileMutationEvidence: hasSuccessfulFileMutationEvidence,
    hasSuccessfulCommandExecutionEvidence:
        hasSuccessfulCommandExecutionEvidence,
  );
}

Map<String, dynamic> _payload(ToolResultInfo result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  group('immutable values', () {
    test('freezes owner evidence and generated results', () {
      final owners = <Object?>['owner-a'];
      final sourceMetadata = <String, dynamic>{
        'paths': <Object?>['lib/original.dart'],
        'owners': owners,
        'labels': <String, dynamic>{'primary': 'owner-a'},
      };
      final sourceArguments = <String, dynamic>{
        'path': 'lib/original.dart',
        'metadata': sourceMetadata,
      };
      final existing = [
        ToolResultInfo(
          id: 'owner-a',
          name: 'write_file',
          arguments: sourceArguments,
          result: '{"ok":true}',
        ),
      ];
      final input = _input(
        content: _toolCall(
          'read_file',
          arguments: const {
            'path': 'lib/main.dart',
            'metadata': {
              'paths': ['lib/main.dart'],
            },
          },
        ),
        existingToolResults: existing,
      );

      existing.clear();
      sourceArguments['path'] = 'lib/changed.dart';
      (sourceMetadata['paths']! as List<Object?>).add('lib/changed.dart');
      owners.add('owner-b');
      (sourceMetadata['labels']! as Map)['secondary'] = 'owner-b';
      final analysis = _policy.analyze(input);

      expect(input.existingToolResults.map((result) => result.id), ['owner-a']);
      expect(input.existingToolResults.single.arguments, {
        'path': 'lib/original.dart',
        'metadata': {
          'paths': ['lib/original.dart'],
          'owners': ['owner-a'],
          'labels': {'primary': 'owner-a'},
        },
      });
      expect(
        () => input.existingToolResults.add(_existingResult(id: 'owner-b')),
        throwsUnsupportedError,
      );
      expect(
        () => input.existingToolResults.single.arguments['path'] =
            'lib/mutated.dart',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((input.existingToolResults.single.arguments['metadata']
                        as Map<String, dynamic>)['owners']
                    as List<Object?>)
                .add('owner-b'),
        throwsUnsupportedError,
      );
      final frozenLabels =
          (input.existingToolResults.single.arguments['metadata']
                  as Map<String, dynamic>)['labels']
              as Map;
      expect(frozenLabels['primary'], 'owner-a');
      expect(() => frozenLabels['primary'] = 'late', throwsUnsupportedError);
      expect(
        () => analysis.newToolResults.add(_existingResult(id: 'new')),
        throwsUnsupportedError,
      );
      expect(
        () => analysis.newToolResults.single.arguments['path'] =
            'lib/mutated.dart',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((analysis.newToolResults.single.arguments['metadata']
                        as Map<String, dynamic>)['paths']
                    as List<Object?>)
                .add('lib/mutated.dart'),
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON owner evidence arguments', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
      ]) {
        expect(
          () => _input(
            content: 'A normal final answer.',
            existingToolResults: [
              _existingResult(arguments: {'invalid': invalidValue}),
            ],
          ),
          throwsArgumentError,
          reason: invalidValue.runtimeType.toString(),
        );
      }
    });
  });

  group('embedded final-answer tool calls', () {
    test('returns an empty analysis for zero or malformed calls', () {
      for (final content in [
        'A normal final answer.',
        '<tool_call>{"name":',
        '```json\n{not-json}\n```',
      ]) {
        final analysis = _policy.analyze(_input(content: content));
        expect(analysis.newToolResults, isEmpty, reason: content);
        expect(analysis.appendNotice, isFalse, reason: content);
        expect(analysis.exitReason, isNull, reason: content);
        expect(analysis.transformId, isNull, reason: content);
        expect(
          analysis.noticeText,
          UnexecutedFinalAnswerToolRequestPolicy.notice,
        );
      }
    });

    test('builds the exact result payload and occurrence-based ID', () {
      final content = _toolCall(
        'read_file',
        arguments: const {'path': 'lib/main.dart', 'reason': 'inspect'},
      );
      final analysis = _policy.analyze(_input(content: content));

      expect(analysis.newToolResults, hasLength(1));
      final result = analysis.newToolResults.single;
      final signature = jsonEncode({
        'name': 'read_file',
        'arguments': {'path': 'lib/main.dart', 'reason': 'inspect'},
      });
      expect(result.id, 'unexecuted_final_answer_0:${content.length}');
      expect(result.name, 'read_file');
      expect(result.arguments, {'path': 'lib/main.dart', 'reason': 'inspect'});
      expect(_payload(result), {
        'ok': false,
        'code': 'tool_call_not_executed',
        'result_origin': 'harness',
        'reason': 'final_answer_tool_request',
        'tool_name': 'read_file',
        'signature': signature,
        'error':
            'The final-answer response requested a tool, but final-answer streaming does not execute tools directly.',
        'required_action':
            'Retry this tool through the normal tool-aware continuation.',
      });
      expect(analysis.appendNotice, isTrue);
      expect(analysis.exitReason, ToolLoopExitReason.unexecutedToolRequest);
      expect(
        analysis.transformId,
        UnexecutedFinalAnswerToolRequestPolicy.transformId,
      );
    });

    test('preserves order while suppressing duplicate signatures', () {
      final duplicate = _toolCall('read_file');
      final content = [
        duplicate,
        _toolCall('write_file'),
        duplicate,
      ].join('\n');
      final analysis = _policy.analyze(_input(content: content));

      expect(analysis.newToolResults.map((result) => result.name).toList(), [
        'read_file',
        'write_file',
      ]);
      expect(
        analysis.newToolResults.map((result) => result.id).toSet(),
        hasLength(2),
      );
    });

    test('suppresses signatures already present in owner evidence', () {
      final signature = jsonEncode({
        'name': 'read_file',
        'arguments': {'path': 'lib/main.dart'},
      });
      final analysis = _policy.analyze(
        _input(
          content: _toolCall('read_file'),
          existingToolResults: [
            _existingResult(id: 'malformed', result: '{not-json'),
            _existingResult(id: 'non-map', result: '[]'),
            _existingResult(
              id: 'recorded',
              result: jsonEncode({
                'reason': 'final_answer_tool_request',
                'signature': signature,
              }),
            ),
          ],
        ),
      );

      expect(analysis.newToolResults, isEmpty);
      expect(analysis.exitReason, isNull);
      expect(analysis.transformId, isNull);
      expect(analysis.appendNotice, isTrue);
    });

    test('keeps result JSON independent of the completed tag spelling', () {
      final toolCall = _policy.analyze(_input(content: _toolCall('read_file')));
      final toolUse = _policy.analyze(
        _input(content: _toolCall('read_file', tag: 'tool_use')),
      );

      expect(
        _payload(toolCall.newToolResults.single),
        _payload(toolUse.newToolResults.single),
      );
      expect(
        toolCall.newToolResults.single.arguments,
        toolUse.newToolResults.single.arguments,
      );
    });

    test('does not append an already-present notice', () {
      final analysis = _policy.analyze(
        _input(
          content:
              '${_toolCall('read_file')}\n'
              '${UnexecutedFinalAnswerToolRequestPolicy.notice}',
        ),
      );

      expect(analysis.newToolResults, hasLength(1));
      expect(analysis.appendNotice, isFalse);
    });

    test('appends notice without recording non-tag structured requests', () {
      const content = '[Tool: edit_file]\nArguments: {"path":"lib/main.dart"}';
      final analysis = _policy.analyze(_input(content: content));

      expect(analysis.newToolResults, isEmpty);
      expect(analysis.appendNotice, isTrue);
      expect(analysis.exitReason, isNull);
      expect(analysis.transformId, isNull);
    });
  });

  group('structured request detection', () {
    test('recognizes completed and bracketed requests', () {
      expect(
        _policy.looksLikeStructuredToolRequest(_toolCall('read_file')),
        isTrue,
      );
      const bracketed =
          '[Tool: edit_file]\nArguments: {"path":"lib/main.dart"}';
      expect(_policy.looksLikeBracketedToolRequest(bracketed), isTrue);
      expect(_policy.bracketedToolRequestName(bracketed), 'edit_file');
      expect(_policy.bracketedToolRequestName('No request.'), isNull);
    });

    test('recognizes fenced and raw command proposal JSON', () {
      for (final content in const [
        '```json\n{"command":"dart test"}\n```',
        '{"name":"local_execute_command","arguments":{"command":"dart test"}}',
        '[{"name":"run_tests","arguments":{}}]',
        '{"NAME":"git_execute_command","ARGUMENTS":{"command":"git status"}}',
        '{"name":"ssh_execute_command","arguments":{"command":"uname"}}',
      ]) {
        expect(
          _policy.looksLikeStructuredToolRequest(content),
          isTrue,
          reason: content,
        );
      }
    });

    test('rejects malformed, result-shaped, and unsupported JSON', () {
      for (final content in const [
        '```json\n{not-json}\n```',
        '```json\n42\n```',
        '[]',
        '{"command":"dart test","exit_code":0,"stdout":"ok"}',
        '{"command":"dart test","stdout":"ok"}',
        '{"command":"dart test","stderr":"failed"}',
        '{"name":"read_file","arguments":{"path":"lib/main.dart"}}',
        '{"name":"run_tests"}',
        '[{"command":"dart test"},42]',
      ]) {
        expect(
          _policy.looksLikeStructuredToolRequest(content),
          isFalse,
          reason: content,
        );
      }
    });

    test('recognizes plan, command, and file-action prose', () {
      const plan = '''
## Plan
1. Inspect the source
2. Run the tests
''';
      expect(_policy.looksLikePlanOnlyFinalToolAnswer(plan), isTrue);
      expect(_policy.looksLikeUnexecutedToolRequest(plan), isTrue);
      expect(
        _policy.looksLikeUnexecutedToolRequest(
          'I will run the command `dart test`.',
        ),
        isTrue,
      );
      expect(
        _policy.looksLikeUnexecutedToolRequest(
          'I will update the file lib/main.dart.',
        ),
        isTrue,
      );
      expect(
        _policy.looksLikeUnexecutedToolRequest('A normal final answer.'),
        isFalse,
      );
    });
  });

  group('notice skip policy', () {
    test('skips notice for completed coding and command evidence', () {
      final coding = _policy.analyze(
        _input(
          content:
              'The Dart implementation completed.\n${_toolCall('read_file')}',
          existingToolResults: [_existingResult(id: 'write')],
          hasSuccessfulFileMutationEvidence: true,
        ),
      );
      final command = _policy.analyze(
        _input(
          content:
              'The command `dart test` completed successfully.\n'
              '${_toolCall('read_file')}',
          existingToolResults: [_existingResult(id: 'command')],
          hasSuccessfulCommandExecutionEvidence: true,
        ),
      );

      expect(coding.appendNotice, isFalse);
      expect(command.appendNotice, isFalse);
      expect(coding.newToolResults, hasLength(1));
      expect(command.newToolResults, hasLength(1));
    });

    test('does not skip when evidence is absent or blocked', () {
      final content =
          'The Dart implementation completed.\n${_toolCall('read_file')}';
      for (final input in [
        _input(content: content),
        _input(
          content: content,
          existingToolResults: [_existingResult(id: 'timeout')],
          hasSuccessfulFileMutationEvidence: true,
          hasTimedOutCommandResult: true,
        ),
        _input(
          content: content,
          existingToolResults: [_existingResult(id: 'failure')],
          hasSuccessfulFileMutationEvidence: true,
          hasFailedCommandValidation: true,
        ),
        _input(
          content: content,
          existingToolResults: [_existingResult(id: 'command-claim')],
          hasSuccessfulFileMutationEvidence: true,
          hasUnexecutedCommandActionResult: true,
        ),
        _input(
          content: content,
          existingToolResults: [_existingResult(id: 'file-claim')],
          hasSuccessfulFileMutationEvidence: true,
          hasUnexecutedFileSideEffectResult: true,
        ),
      ]) {
        expect(_policy.analyze(input).appendNotice, isTrue);
      }
    });

    test('does not skip empty, structured, plan, or future candidates', () {
      final success = [_existingResult(id: 'success')];
      for (final content in [
        _toolCall('read_file'),
        '[Tool: read_file]\nArguments: {"path":"lib/main.dart"}',
        '## Plan\n1. I will inspect the Dart source\n2. I will run tests',
        'I will run the command `dart test`.',
        'I will update the file lib/main.dart.',
        'I will inspect the Dart source.\n${_toolCall('read_file')}',
      ]) {
        final analysis = _policy.analyze(
          _input(
            content: content,
            existingToolResults: success,
            hasSuccessfulFileMutationEvidence: true,
          ),
        );
        expect(analysis.appendNotice, isTrue, reason: content);
      }
    });

    test('does not skip beyond the completed-answer length limit', () {
      final longCompletion =
          'The Dart implementation completed. ${List.filled(1700, 'x').join()}';
      final analysis = _policy.analyze(
        _input(
          content: '$longCompletion\n${_toolCall('read_file')}',
          existingToolResults: [_existingResult(id: 'owner-a')],
          hasSuccessfulFileMutationEvidence: true,
        ),
      );

      expect(analysis.newToolResults, hasLength(1));
      expect(analysis.appendNotice, isTrue);
    });

    test('uses only the supplied owner evidence in a poison case', () {
      final content =
          'The Dart implementation completed.\n${_toolCall('read_file')}';
      final ownerA = _input(
        content: content,
        existingToolResults: [_existingResult(id: 'owner-a')],
        hasSuccessfulFileMutationEvidence: true,
      );
      final visibleOwnerB = _input(
        content: content,
        existingToolResults: [_existingResult(id: 'owner-b')],
        hasTimedOutCommandResult: true,
      );

      expect(_policy.analyze(ownerA).appendNotice, isFalse);
      expect(_policy.analyze(visibleOwnerB).appendNotice, isTrue);
    });
  });
}
