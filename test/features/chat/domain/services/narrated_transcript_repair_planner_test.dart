import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/narrated_transcript_repair_planner.dart';
import 'package:test/test.dart';

const _planner = NarratedTranscriptRepairPlanner();
const _candidate = '''
Verification:

```bash
\$ dart test
All tests passed!
```
''';

ToolResultInfo _commandResult(String command) {
  return ToolResultInfo(
    id: 'command-result',
    name: 'local_execute_command',
    arguments: {'command': command},
    result: '{"exit_code":0}',
  );
}

NarratedTranscriptRepairInput _input({
  required ChatTurnOwner owner,
  bool verificationEnabled = true,
  bool isCodingWorkspaceOrMode = true,
  bool isPlanning = false,
  String candidateResponse = _candidate,
  List<ToolResultInfo> ownerToolResults = const [],
  List<String> ownerExecutedCommands = const [],
  Set<String> attemptedSignatures = const {},
  int maximumAttempts = 2,
  String feedbackId = 'feedback-owner-a',
}) {
  return NarratedTranscriptRepairInput(
    owner: owner,
    verificationEnabled: verificationEnabled,
    isCodingWorkspaceOrMode: isCodingWorkspaceOrMode,
    isPlanning: isPlanning,
    candidateResponse: candidateResponse,
    ownerToolResults: ownerToolResults,
    ownerExecutedCommands: ownerExecutedCommands,
    attemptedSignatures: attemptedSignatures,
    maximumAttempts: maximumAttempts,
    feedbackId: feedbackId,
  );
}

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'owner-a',
    interactionGeneration: 7,
  );

  test('freezes owner evidence and generated plan collections', () {
    final metadata = <String, dynamic>{
      'commands': <Object?>['dart analyze'],
      'owners': <Object?>['owner-a'],
      'labels': <String, dynamic>{'primary': 'owner-a'},
    };
    final originalArguments = <String, dynamic>{
      'command': 'dart analyze',
      'metadata': metadata,
    };
    final toolResults = <ToolResultInfo>[
      ToolResultInfo(
        id: 'original',
        name: 'local_execute_command',
        arguments: originalArguments,
        result: '{"exit_code":0}',
      ),
    ];
    final commands = <String>[];
    final attemptedSignatures = <String>{};
    final input = _input(
      owner: ownerA,
      ownerToolResults: toolResults,
      ownerExecutedCommands: commands,
      attemptedSignatures: attemptedSignatures,
    );

    toolResults.clear();
    originalArguments['command'] = 'dart test';
    (metadata['commands']! as List<Object?>).add('dart test');
    (metadata['owners']! as List<Object?>).add('owner-b');
    (metadata['labels']! as Map)['primary'] = 'owner-b';
    commands.add('dart test');
    attemptedSignatures.add('external-change');

    expect(input.ownerToolResults, hasLength(1));
    expect(input.ownerToolResults.single.arguments, {
      'command': 'dart analyze',
      'metadata': {
        'commands': ['dart analyze'],
        'owners': ['owner-a'],
        'labels': {'primary': 'owner-a'},
      },
    });
    final frozenLabels =
        (input.ownerToolResults.single.arguments['metadata']
                as Map<String, dynamic>)['labels']
            as Map;
    expect(frozenLabels['primary'], 'owner-a');
    expect(input.ownerExecutedCommands, isEmpty);
    expect(input.attemptedSignatures, isEmpty);
    expect(
      () => input.ownerToolResults.add(_commandResult('dart analyze')),
      throwsUnsupportedError,
    );
    expect(
      () => input.ownerToolResults.single.arguments['command'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((input.ownerToolResults.single.arguments['metadata']
                      as Map<String, dynamic>)['commands']
                  as List<Object?>)
              .add('dart format'),
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((input.ownerToolResults.single.arguments['metadata']
                      as Map<String, dynamic>)['owners']
                  as List<Object?>)
              .add('owner-c'),
      throwsUnsupportedError,
    );
    expect(() => frozenLabels['primary'] = 'late', throwsUnsupportedError);
    expect(
      () => input.ownerExecutedCommands.add('dart analyze'),
      throwsUnsupportedError,
    );
    expect(
      () => input.attemptedSignatures.add('another'),
      throwsUnsupportedError,
    );

    final plan = _planner.plan(input)!;
    expect(
      () => plan.assessment.unexecutedCommands.add('dart analyze'),
      throwsUnsupportedError,
    );
    expect(
      () => plan.feedback.arguments['trigger'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => (plan.feedback.arguments['unexecuted_commands'] as List<String>)
          .add('dart analyze'),
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
          owner: ownerA,
          ownerToolResults: [
            ToolResultInfo(
              id: 'invalid',
              name: 'read_file',
              arguments: {'invalid': invalidValue},
              result: '{"ok":true}',
            ),
          ],
        ),
        throwsArgumentError,
        reason: invalidValue.runtimeType.toString(),
      );
    }
  });

  test('rejects disabled, non-coding, and planning owner states', () {
    final cases =
        <
          ({
            String label,
            bool verificationEnabled,
            bool isCoding,
            bool isPlanning,
          })
        >[
          (
            label: 'disabled',
            verificationEnabled: false,
            isCoding: true,
            isPlanning: false,
          ),
          (
            label: 'non-coding',
            verificationEnabled: true,
            isCoding: false,
            isPlanning: false,
          ),
          (
            label: 'planning',
            verificationEnabled: true,
            isCoding: true,
            isPlanning: true,
          ),
        ];

    for (final entry in cases) {
      expect(
        _planner.plan(
          _input(
            owner: ownerA,
            verificationEnabled: entry.verificationEnabled,
            isCodingWorkspaceOrMode: entry.isCoding,
            isPlanning: entry.isPlanning,
          ),
        ),
        isNull,
        reason: entry.label,
      );
    }
  });

  test('returns no plan when every narrated command has owner evidence', () {
    expect(
      _planner.plan(
        _input(owner: ownerA, ownerExecutedCommands: const ['dart test']),
      ),
      isNull,
    );
    expect(
      _planner.plan(
        _input(owner: ownerA, ownerToolResults: [_commandResult('dart test')]),
      ),
      isNull,
    );
  });

  test('rejects a repeated signature without mutating the owner set', () {
    final attemptedSignatures = <String>{
      jsonEncode(['dart test']),
    };
    final input = _input(
      owner: ownerA,
      attemptedSignatures: attemptedSignatures,
    );
    final disposition = _planner.evaluate(input);

    expect(disposition.plan, isNull);
    expect(
      disposition.noPlanReason,
      NarratedTranscriptRepairNoPlanReason.repeatedSignature,
    );
    expect(_planner.plan(input), isNull);
    expect(attemptedSignatures, {
      jsonEncode(['dart test']),
    });
  });

  test('rejects repair after the configured attempt limit', () {
    final atLimit = _input(
      owner: ownerA,
      attemptedSignatures: const {'first', 'second'},
      maximumAttempts: 2,
    );
    final zeroLimit = _input(owner: ownerA, maximumAttempts: 0);

    for (final input in [atLimit, zeroLimit]) {
      final disposition = _planner.evaluate(input);
      expect(disposition.plan, isNull);
      expect(
        disposition.noPlanReason,
        NarratedTranscriptRepairNoPlanReason.attemptLimitReached,
      );
      expect(_planner.plan(input), isNull);
    }
  });

  test('builds the exact successful repair plan and feedback payload', () {
    final input = _input(
      owner: ownerA,
      feedbackId: 'narrated_transcript_check_explicit',
    );
    final disposition = _planner.evaluate(input);
    final plan = _planner.plan(input)!;

    expect(disposition.plan, isNotNull);
    expect(disposition.noPlanReason, isNull);
    expect(plan.owner, same(ownerA));
    expect(plan.signature, jsonEncode(['dart test']));
    expect(plan.assessment.unexecutedCommands, ['dart test']);
    expect(plan.feedback.id, 'narrated_transcript_check_explicit');
    expect(plan.feedback.name, 'narrated_transcript_check');
    expect(plan.feedback.arguments, {
      'trigger': 'narratedTranscript',
      'unexecuted_commands': ['dart test'],
    });
    expect(jsonDecode(plan.feedback.result), {
      'schema': 'caverno_narrated_transcript_check',
      'ok': false,
      'code': 'narrated_transcript_commands_not_executed',
      'unexecuted_commands': ['dart test'],
      'error':
          'The answer presents a terminal transcript, but these commands '
          'have no execution record in this turn, so the output shown for '
          'them is not a real observation.',
      'required_action':
          'Execute the narrated commands now with local_execute_command '
          'and base the answer on their real output, or rewrite the answer '
          'to state plainly that these checks were not run.',
    });
  });

  test('uses deterministic explicit IDs without changing the signature', () {
    final first = _planner.plan(
      _input(owner: ownerA, feedbackId: 'feedback-1'),
    )!;
    final second = _planner.plan(
      _input(owner: ownerA, feedbackId: 'feedback-2'),
    )!;

    expect(first.feedback.id, 'feedback-1');
    expect(second.feedback.id, 'feedback-2');
    expect(first.signature, second.signature);
    expect(first.feedback.result, second.feedback.result);
  });

  test('keeps equal-generation owners independent in the poison case', () {
    final ownerB = ChatTurnOwner(
      conversationId: 'owner-b',
      interactionGeneration: ownerA.interactionGeneration,
    );
    final ownerAAttempts = <String>{};
    final ownerBAttempts = <String>{};

    final firstOwnerAPlan = _planner.plan(
      _input(owner: ownerA, attemptedSignatures: ownerAAttempts),
    )!;
    ownerAAttempts.add(firstOwnerAPlan.signature);

    final repeatedOwnerAPlan = _planner.plan(
      _input(owner: ownerA, attemptedSignatures: ownerAAttempts),
    );
    final firstOwnerBPlan = _planner.plan(
      _input(
        owner: ownerB,
        attemptedSignatures: ownerBAttempts,
        feedbackId: 'feedback-owner-b',
      ),
    );

    expect(repeatedOwnerAPlan, isNull);
    expect(firstOwnerBPlan, isNotNull);
    expect(firstOwnerBPlan!.owner, same(ownerB));
    expect(firstOwnerBPlan.feedback.id, 'feedback-owner-b');
    expect(ownerBAttempts, isEmpty);
  });

  test('keeps peer command evidence out of the owner repair decision', () {
    final ownerB = ChatTurnOwner(
      conversationId: 'owner-b',
      interactionGeneration: ownerA.interactionGeneration,
    );

    final ownerAPlan = _planner.plan(_input(owner: ownerA));
    final ownerBPlan = _planner.plan(
      _input(owner: ownerB, ownerExecutedCommands: const ['dart test']),
    );

    expect(ownerAPlan, isNotNull);
    expect(ownerAPlan!.owner, same(ownerA));
    expect(ownerBPlan, isNull);
  });
}
