import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_continuation_recovery_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _policy = CodingContinuationRecoveryPolicy();

Map<String, dynamic> _toolDefinition(String name) {
  return {
    'type': 'function',
    'function': {'name': name},
  };
}

CodingContinuationRecoveryInput _input({
  String candidateResponse = 'I will inspect the Dart source.',
  List<Map<String, dynamic>>? toolDefinitions,
  String owningTurnLatestUserText = 'continue',
  bool requireContinuationRequest = true,
  bool isCodingWorkspaceOrMode = true,
  bool hasPendingAutoContinueWorkflow = false,
  bool saveSkillCompletedInGeneration = false,
  bool acceptsTerminalToolRoleBlockerResponse = false,
  String? bracketedToolRequestName,
}) {
  return CodingContinuationRecoveryInput(
    candidateResponse: candidateResponse,
    toolDefinitions: toolDefinitions ?? [_toolDefinition('read_file')],
    owningTurnLatestUserText: owningTurnLatestUserText,
    requireContinuationRequest: requireContinuationRequest,
    isCodingWorkspaceOrMode: isCodingWorkspaceOrMode,
    hasPendingAutoContinueWorkflow: hasPendingAutoContinueWorkflow,
    saveSkillCompletedInGeneration: saveSkillCompletedInGeneration,
    acceptsTerminalToolRoleBlockerResponse:
        acceptsTerminalToolRoleBlockerResponse,
    bracketedToolRequestName: bracketedToolRequestName,
  );
}

ToolResultInfo _result({
  String id = 'result',
  String name = 'local_execute_command',
  String result = '{"exit_code":0}',
  ToolOutcome? outcome,
}) {
  return ToolResultInfo(
    id: id,
    name: name,
    arguments: const {},
    result: result,
    outcome: outcome,
  );
}

void main() {
  group('CodingContinuationRecoveryInput', () {
    test('freezes the supplied tool definition list and entries', () {
      final definition = _toolDefinition('read_file');
      final function = definition['function']! as Map<String, dynamic>;
      final ownerMetadata = <String, dynamic>{
        'primary': <Object?>['owner-a'],
      };
      final tags = <Object?>['owner-a'];
      definition['metadata'] = <String, dynamic>{
        'owners': ownerMetadata,
        'tags': tags,
      };
      final definitions = [definition];
      final input = _input(toolDefinitions: definitions);

      definitions.clear();
      definition['type'] = 'changed';
      function['name'] = 'get_datetime';
      (ownerMetadata['primary']! as List<Object?>).add('visible-owner-b');
      tags.add('visible-owner-b');

      expect(input.toolDefinitions, hasLength(1));
      expect(input.toolDefinitions.single['type'], 'function');
      expect(
        (input.toolDefinitions.single['function']! as Map)['name'],
        'read_file',
      );
      final frozenMetadata =
          input.toolDefinitions.single['metadata']! as Map<String, dynamic>;
      final frozenOwners = frozenMetadata['owners']! as Map<String, dynamic>;
      final frozenTags = frozenMetadata['tags']! as List<Object?>;
      expect(frozenOwners['primary'], ['owner-a']);
      expect(frozenTags, ['owner-a']);
      expect(
        () => input.toolDefinitions.add(_toolDefinition('write_file')),
        throwsUnsupportedError,
      );
      expect(
        () => input.toolDefinitions.single['type'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => (input.toolDefinitions.single['function']! as Map)['name'] =
            'changed',
        throwsUnsupportedError,
      );
      expect(
        () => (frozenOwners['primary']! as List<Object?>).add('later poison'),
        throwsUnsupportedError,
      );
      expect(() => frozenTags.add('later poison'), throwsUnsupportedError);
    });

    test('rejects non-JSON tool-definition values', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
      ]) {
        final definition = _toolDefinition('read_file')
          ..['metadata'] = <String, dynamic>{'invalid': invalidValue};

        expect(
          () => _input(toolDefinitions: [definition]),
          throwsArgumentError,
          reason: invalidValue.runtimeType.toString(),
        );
      }
    });
  });

  group('recoveryCode', () {
    test('returns no recovery for each terminal precondition', () {
      expect(_policy.recoveryCode(_input(candidateResponse: '  ')), isNull);
      expect(
        _policy.recoveryCode(_input(isCodingWorkspaceOrMode: false)),
        isNull,
      );
      expect(
        _policy.recoveryCode(
          _input(toolDefinitions: [_toolDefinition('get_datetime')]),
        ),
        isNull,
      );
      expect(
        _policy.recoveryCode(_input(saveSkillCompletedInGeneration: true)),
        isNull,
      );
      expect(
        _policy.recoveryCode(
          _input(acceptsTerminalToolRoleBlockerResponse: true),
        ),
        isNull,
      );
    });

    test('requires an owning-turn continuation request when configured', () {
      expect(
        _policy.recoveryCode(
          _input(owningTurnLatestUserText: 'Implement the feature.'),
        ),
        isNull,
      );
      expect(
        _policy.recoveryCode(
          _input(
            owningTurnLatestUserText: 'Implement the feature.',
            requireContinuationRequest: false,
          ),
        ),
        'prose_only_coding_continuation',
      );
    });

    test('recovers only pending structured execution deferrals', () {
      const structuredDeferral = '''
## Next implementation step

1. Read lib/main.dart
2. Implement the parser
''';

      expect(
        _policy.recoveryCode(
          _input(
            candidateResponse: structuredDeferral,
            owningTurnLatestUserText: 'Implement the parser.',
          ),
        ),
        isNull,
      );
      expect(
        _policy.recoveryCode(
          _input(
            candidateResponse: structuredDeferral,
            owningTurnLatestUserText: 'Implement the parser.',
            hasPendingAutoContinueWorkflow: true,
          ),
        ),
        'prose_only_coding_continuation',
      );
    });

    test('prioritizes executable bracketed coding tool requests', () {
      expect(
        _policy.recoveryCode(
          _input(
            candidateResponse: 'I will inspect the Dart source.',
            bracketedToolRequestName: ' EDIT_FILE ',
          ),
        ),
        'bracketed_coding_tool_request',
      );
      expect(
        _policy.recoveryCode(
          _input(
            candidateResponse: 'Arguments follow.',
            bracketedToolRequestName: 'get_datetime',
          ),
        ),
        isNull,
      );
    });

    test('applies terminal gates before bracketed-request recovery', () {
      for (final input in [
        _input(
          bracketedToolRequestName: 'edit_file',
          saveSkillCompletedInGeneration: true,
        ),
        _input(
          bracketedToolRequestName: 'edit_file',
          acceptsTerminalToolRoleBlockerResponse: true,
        ),
        _input(
          bracketedToolRequestName: 'edit_file',
          owningTurnLatestUserText: 'Implement the feature.',
        ),
      ]) {
        expect(_policy.recoveryCode(input), isNull);
      }
    });

    test('recovers ordinary prose-only coding continuations', () {
      expect(_policy.recoveryCode(_input()), 'prose_only_coding_continuation');
      expect(
        _policy.recoveryCode(
          _input(candidateResponse: 'The requested answer is complete.'),
        ),
        isNull,
      );
    });

    test('uses only the supplied owner snapshot in a poison-thread case', () {
      final ownerA = _input(
        candidateResponse: 'I will inspect the Dart source.',
        owningTurnLatestUserText: 'continue',
        hasPendingAutoContinueWorkflow: true,
      );
      final visibleThreadB = _input(
        candidateResponse: ownerA.candidateResponse,
        owningTurnLatestUserText: 'Summarize the release notes.',
        isCodingWorkspaceOrMode: false,
        hasPendingAutoContinueWorkflow: false,
        saveSkillCompletedInGeneration: true,
      );

      expect(_policy.recoveryCode(ownerA), 'prose_only_coding_continuation');
      expect(_policy.recoveryCode(visibleThreadB), isNull);
    });
  });

  group('tool availability', () {
    test('recognizes every supported tool name after normalization', () {
      const supportedNames = {
        'read_file',
        'list_directory',
        'search_files',
        'resolve_installed_dependency',
        'write_file',
        'edit_file',
        'delete_file',
        'local_execute_command',
        'git_execute_command',
        'run_tests',
        'run_python_script',
      };

      for (final name in supportedNames) {
        expect(
          _policy.isCodingContinuationRecoveryToolName(
            ' ${name.toUpperCase()} ',
          ),
          isTrue,
          reason: name,
        );
      }
      expect(
        _policy.isCodingContinuationRecoveryToolName('get_datetime'),
        isFalse,
      );
      expect(
        _policy.hasCodingContinuationRecoveryTools([
          _toolDefinition('get_datetime'),
          _toolDefinition(' RUN_TESTS '),
        ]),
        isTrue,
      );
      expect(
        _policy.hasCodingContinuationRecoveryTools([
          _toolDefinition('get_datetime'),
          {'type': 'function'},
        ]),
        isFalse,
      );
    });
  });

  group('looksLikeContinuationOnlyUserRequest', () {
    test('recognizes English continuation-only requests', () {
      for (final request in const [
        'continue',
        'Go on',
        'keep going',
        'proceed',
        'resume',
        'next',
        'next step',
        '... Continue!?',
        'automatic goal continuation turn 3',
      ]) {
        expect(
          _policy.looksLikeContinuationOnlyUserRequest(request),
          isTrue,
          reason: request,
        );
      }
      expect(_policy.looksLikeContinuationOnlyUserRequest(''), isFalse);
      expect(
        _policy.looksLikeContinuationOnlyUserRequest('continue the task'),
        isFalse,
      );
    });

    test('recognizes CJK continuation markers', () {
      for (final codeUnits in const [
        [0x7d9a, 0x3051, 0x3066],
        [0x7d9a, 0x304d],
        [0x9032, 0x3081, 0x3066],
      ]) {
        expect(
          _policy.looksLikeContinuationOnlyUserRequest(
            String.fromCharCodes(codeUnits),
          ),
          isTrue,
        );
      }
    });
  });

  group('looksLikeProseOnlyCodingContinuation', () {
    test('recognizes English and CJK future coding actions', () {
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(
          'Next I will inspect the Dart source.',
        ),
        isTrue,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(
          String.fromCharCodes([
            0x30b3,
            0x30fc,
            0x30c9,
            0x3092,
            0x5b9f,
            0x88c5,
            0x3057,
            0x307e,
            0x3059,
          ]),
        ),
        isTrue,
      );
    });

    test('rejects empty, blocked, incomplete, and oversized prose', () {
      expect(_policy.looksLikeProseOnlyCodingContinuation(''), isFalse);
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(
          'I cannot inspect the Dart source.',
        ),
        isFalse,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(
          'The Dart source is ready.',
        ),
        isFalse,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation('Next I will continue.'),
        isFalse,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(
          'I will inspect the Dart source. ${'x' * 1600}',
        ),
        isFalse,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(
          'I will inspect the Dart source. ```${'x' * 12000}```',
        ),
        isFalse,
      );
    });

    test('allows a bounded fenced-code continuation', () {
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(
          'I will inspect the Dart source. ```${'x' * 1700}```',
        ),
        isTrue,
      );
    });

    test('preserves the exact prose and fenced-code length limits', () {
      const lead = 'I will inspect the Dart source. ';
      final proseAtLimit = '$lead${'x' * (1600 - lead.length)}';
      final proseOverLimit = '$lead${'x' * (1601 - lead.length)}';
      const fencedLead = 'I will inspect the Dart source. ```';
      const fencedTail = '```';
      final fencedAtLimit =
          '$fencedLead'
          '${'x' * (12000 - fencedLead.length - fencedTail.length)}'
          '$fencedTail';
      final fencedOverLimit =
          '$fencedLead'
          '${'x' * (12001 - fencedLead.length - fencedTail.length)}'
          '$fencedTail';

      expect(proseAtLimit.length, 1600);
      expect(proseOverLimit.length, 1601);
      expect(fencedAtLimit.length, 12000);
      expect(fencedOverLimit.length, 12001);
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(proseAtLimit),
        isTrue,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(proseOverLimit),
        isFalse,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(fencedAtLimit),
        isTrue,
      );
      expect(
        _policy.looksLikeProseOnlyCodingContinuation(fencedOverLimit),
        isFalse,
      );
    });
  });

  group('recovery payload copy', () {
    test('preserves every recovery-code label and payload', () {
      const expectations = {
        'length_truncated_pending_action': {
          'label': 'length-truncated pending action recovery',
          'reason':
              'The assistant reached the output-token limit while trusted tool evidence still showed incomplete executable coding work.',
          'error':
              'The assistant reached the output-token limit before issuing the next executable coding action.',
          'action':
              'Issue exactly one available tool call that advances the incomplete work.',
        },
        'bracketed_coding_tool_request': {
          'label': 'bracketed coding tool request recovery',
          'reason':
              'The assistant returned a bracketed coding tool request in final-answer text instead of issuing an executable tool call.',
          'error':
              'The assistant response contained a bracketed coding tool request, but no executable tool call was issued.',
          'action':
              'Issue the requested coding tool call now. Do not describe bracketed tool blocks as already executed.',
        },
        'prose_only_coding_continuation': {
          'label': 'prose-only coding continuation recovery',
          'reason':
              'The assistant returned coding continuation prose instead of using an available coding tool.',
          'error':
              'The assistant response described a future coding action, but no tool call was issued.',
          'action':
              'Use an available file, command, or test tool now. Do not restate the plan.',
        },
      };

      for (final entry in expectations.entries) {
        final recoveryCode = entry.key;
        final expected = entry.value;
        expect(_policy.recoveryLogLabel(recoveryCode), expected['label']);
        expect(_policy.recoveryReason(recoveryCode), expected['reason']);
        expect(_policy.recoveryError(recoveryCode), expected['error']);
        expect(
          _policy.recoveryRequiredAction(recoveryCode),
          expected['action'],
        );

        final result = _policy.buildCodingContinuationRecoveryToolResult(
          id: 'fixed-$recoveryCode',
          candidateResponse: '  Claimed   response  ',
          recoveryCode: recoveryCode,
        );
        final payload = jsonDecode(result.result) as Map<String, dynamic>;
        expect(result.id, 'fixed-$recoveryCode');
        expect(result.name, 'coding_continuation_recovery');
        expect(result.arguments, {'reason': expected['reason']});
        expect(payload, {
          'ok': false,
          'code': recoveryCode,
          'error': expected['error'],
          'claimedResponse': 'Claimed response',
          'requiredAction': expected['action'],
        });
      }
    });
  });

  group('recovery prompt', () {
    test('builds the default prose and bracketed prompts', () {
      final prosePrompt = _policy.buildCodingContinuationRecoveryPrompt(
        '  I will   inspect the source.  ',
        recoveryCode: 'prose_only_coding_continuation',
      );
      expect(
        prosePrompt,
        startsWith(
          'The previous assistant response was a coding continuation, but no tool call was issued.',
        ),
      );
      expect(prosePrompt, contains('Treat that response as unexecuted.'));
      expect(
        prosePrompt,
        contains('Previous response: I will inspect the source.'),
      );

      final bracketedPrompt = _policy.buildCodingContinuationRecoveryPrompt(
        'Arguments follow.',
        recoveryCode: 'bracketed_coding_tool_request',
      );
      expect(
        bracketedPrompt,
        startsWith(
          'The previous assistant response contained a bracketed coding tool request in final-answer text, but no tool call was issued.',
        ),
      );
    });

    test('preserves successful work around timeout and exit failure', () {
      final prompt = _policy.buildCodingContinuationRecoveryPrompt(
        'I will fix the remaining failure.',
        recoveryCode: 'prose_only_coding_continuation',
        executedToolResults: [
          _result(id: 'success'),
          _result(id: 'timeout', result: '{"timed_out":true}'),
          _result(id: 'failure', result: '{"exit_code":2}'),
        ],
      );

      expect(
        prompt,
        contains(
          'Some commands in this turn already completed successfully, but '
          'a command timed out before completing and '
          'a command exited with a non-zero status.',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not restart the task or re-run commands that already completed successfully.',
        ),
      );
      expect(prompt, isNot(contains('Treat that response as unexecuted.')));
    });

    test('describes a lone raw exit-code failure without prior progress', () {
      expect(
        _policy.recoveryPartialProgressNotice([
          _result(result: 'exit_code: 3'),
        ]),
        'In this turn, a command exited with a non-zero status.',
      );
    });

    test('prefers typed exit status over contradictory payload text', () {
      expect(
        _policy.recoveryPartialProgressNotice([
          _result(
            result: '{"exit_code":0}',
            outcome: const ToolOutcome(exitCode: 3),
          ),
        ]),
        'In this turn, a command exited with a non-zero status.',
      );
      expect(
        _policy.recoveryPartialProgressNotice([
          _result(
            result: '{"exit_code":3}',
            outcome: const ToolOutcome(exitCode: 0),
          ),
        ]),
        isNull,
      );
    });

    test('uses the default prompt for successful or read-only evidence', () {
      expect(_policy.recoveryPartialProgressNotice(const []), isNull);
      expect(_policy.recoveryPartialProgressNotice([_result()]), isNull);
      expect(
        _policy.recoveryPartialProgressNotice([
          _result(
            name: 'read_file',
            result: '{"exit_code":2,"content":"context"}',
          ),
        ]),
        isNull,
      );
    });

    test('clips long diagnostic text in prompts', () {
      final prompt = _policy.buildCodingContinuationRecoveryPrompt(
        'word ${'x' * 260}',
        recoveryCode: 'prose_only_coding_continuation',
      );

      expect(prompt, contains('Previous response: word '));
      expect(prompt, endsWith('...'));
    });
  });
}
