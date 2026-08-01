import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_tracker_registry.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:test/test.dart';

ChatTurnOwner _owner(String conversationId, {int generation = 1}) =>
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    );

GoalAutoContinueConversationTaskSnapshot _context(
  ChatTurnOwner owner, {
  WorkspaceMode workspaceMode = WorkspaceMode.coding,
  String? activeTaskId = 'task-a',
  int mutationGeneration = 1,
  int verificationGeneration = -1,
}) => (
  owner: owner,
  workspaceMode: workspaceMode,
  activeTaskId: activeTaskId,
  mutationGeneration: mutationGeneration,
  verificationGeneration: verificationGeneration,
);

ToolCallInfo _call(
  String id,
  String name, {
  Map<String, dynamic> arguments = const {},
}) => ToolCallInfo(id: id, name: name, arguments: arguments);

ToolCallInfo _command(String id, String command, {bool background = false}) =>
    _call(
      id,
      'local_execute_command',
      arguments: {
        'command': command,
        if (background) 'background': true,
        'working_directory': '/workspace',
      },
    );

ToolResultCompletionEvidence _mutationEvidence() =>
    const ToolResultCompletionEvidence(
      mutatedWithoutExecutionVerification: true,
      unverifiedChangePaths: ['lib/main.dart'],
    );

void main() {
  group('GoalAutoContinueTrackerRegistry lifecycle', () {
    test('creates, reads, and updates durable conversation tracking', () {
      final ownerA = _owner('conversation-a', generation: 4);
      final ownerANext = _owner('conversation-a', generation: 5);
      final fixture = _Fixture();

      expect(fixture.registry.read(ownerA), isNull);
      final initial = fixture.registry.create(ownerA);

      expect(initial.consecutiveAutoContinuations, 0);
      expect(initial.diagnosticRepairContinuations, 0);
      expect(initial.diagnosticRepairExtensionUsed, isFalse);
      expect(initial.noProgressStreak, 0);
      expect(initial.consecutiveValidationMisses, 0);
      expect(initial.failedVerificationObserved, isFalse);
      expect(initial.previousEvidence, isNull);
      expect(initial.previousDiagnosticSignature, isEmpty);
      expect(initial.identicalDiagnosticSignatureStreak, 0);
      expect(initial.pendingPostRepairReplayOutcome, isFalse);
      expect(initial.pendingRepairContractOutcome, isFalse);
      expect(initial.repairNoMutationRetryUsed, isFalse);
      expect(initial.completionElicitationMutationGeneration, isNull);
      expect(initial.activeCommandDiagnosticRepairFocus, isNull);
      expect(initial.verifierReplayCandidate, isNull);
      expect(initial.replayedMutationGenerations, isEmpty);
      expect(initial.replayedInteractionGenerations, isEmpty);
      expect(initial.budgetNoticePresented, isFalse);

      final updated = fixture.registry.update(
        ownerA,
        consecutiveAutoContinuationsDelta: 2,
        diagnosticRepairContinuationsDelta: 1,
        diagnosticRepairExtensionUsed: true,
        noProgressStreak: 3,
        consecutiveValidationMisses: 4,
        failedVerificationObserved: true,
        previousEvidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 2,
          diagnosticSignature: 'signature-a',
        ),
        previousDiagnosticSignature: 'signature-a',
        identicalDiagnosticSignatureStreak: 5,
        pendingPostRepairReplayOutcome: true,
        pendingRepairContractOutcome: true,
        repairNoMutationRetryUsed: true,
        completionElicitationMutationGeneration: 7,
      );

      expect(updated.consecutiveAutoContinuations, 2);
      expect(updated.diagnosticRepairContinuations, 1);
      expect(updated.diagnosticRepairExtensionUsed, isTrue);
      expect(updated.noProgressStreak, 3);
      expect(updated.consecutiveValidationMisses, 4);
      expect(updated.failedVerificationObserved, isTrue);
      expect(updated.previousEvidence?.unresolvedErrorCount, 2);
      expect(updated.previousDiagnosticSignature, 'signature-a');
      expect(updated.identicalDiagnosticSignatureStreak, 5);
      expect(updated.pendingPostRepairReplayOutcome, isTrue);
      expect(updated.pendingRepairContractOutcome, isTrue);
      expect(updated.repairNoMutationRetryUsed, isTrue);
      expect(updated.completionElicitationMutationGeneration, 7);

      final fromNextGeneration = fixture.registry.read(ownerANext)!;
      expect(fromNextGeneration.consecutiveAutoContinuations, 2);
      expect(fromNextGeneration.previousDiagnosticSignature, 'signature-a');
      expect(fromNextGeneration.verifierReplayCandidate, isNull);
      expect(fromNextGeneration.replayedInteractionGenerations, isEmpty);

      final incremented = fixture.registry.update(
        ownerANext,
        consecutiveAutoContinuationsDelta: 1,
      );
      expect(incremented.consecutiveAutoContinuations, 3);
      expect(incremented.diagnosticRepairContinuations, 1);
      expect(incremented.noProgressStreak, 3);
      expect(incremented.pendingRepairContractOutcome, isTrue);
      expect(fixture.registry.create(ownerA).consecutiveAutoContinuations, 3);
    });

    test('explicitly clears nullable tracker fields without resetting', () {
      final owner = _owner('conversation-a', generation: 4);
      final fixture = _Fixture();
      fixture.registry.update(
        owner,
        noProgressStreak: 3,
        previousEvidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 1,
        ),
        completionElicitationMutationGeneration: 7,
      );

      final cleared = fixture.registry.update(
        owner,
        clearPreviousEvidence: true,
        clearCompletionElicitationMutationGeneration: true,
      );

      expect(cleared.noProgressStreak, 3);
      expect(cleared.previousEvidence, isNull);
      expect(cleared.completionElicitationMutationGeneration, isNull);
    });

    test('rejects setting and clearing a nullable field together', () {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();

      expect(
        () => fixture.registry.update(
          owner,
          previousEvidence: const ToolResultCompletionEvidence(),
          clearPreviousEvidence: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => fixture.registry.update(
          owner,
          completionElicitationMutationGeneration: 3,
          clearCompletionElicitationMutationGeneration: true,
        ),
        throwsArgumentError,
      );
      expect(fixture.registry.read(owner), isNull);
    });

    test('defensively copies evidence and immutable snapshot collections', () {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();
      final toolNames = <String>['run_tests'];
      final errorPaths = <String>['lib/a.dart'];
      final diagnostics = <UnresolvedErrorDiagnostic>[
        const UnresolvedErrorDiagnostic(
          path: 'lib/a.dart',
          code: 'compile_error',
          message: 'Compilation failed.',
        ),
      ];
      final changePaths = <String>['lib/b.dart'];
      final evidence = ToolResultCompletionEvidence(
        boundedToolLoopExhausted: true,
        unexecutedToolNames: toolNames,
        unresolvedErrorCount: 1,
        unresolvedErrorPaths: errorPaths,
        unresolvedErrorDiagnostics: diagnostics,
        unverifiedChangePaths: changePaths,
        mutatedWithoutExecutionVerification: true,
        hasExecutionVerification: true,
        hasSuccessfulExecutionVerification: false,
        hasFailedExecutionVerification: true,
        hasAuthoritativeDiagnosticSnapshot: true,
        hasUnexecutedActionClaim: true,
        diagnosticSignature: 'signature-a',
      );

      fixture.registry.update(owner, previousEvidence: evidence);
      toolNames.add('local_execute_command');
      errorPaths.add('lib/poison.dart');
      diagnostics.add(
        const UnresolvedErrorDiagnostic(
          path: 'lib/poison.dart',
          code: 'poison',
          message: 'Poisoned.',
        ),
      );
      changePaths.add('lib/poison.dart');

      final stored = fixture.registry.read(owner)!.previousEvidence!;
      expect(stored.unexecutedToolNames, ['run_tests']);
      expect(stored.unresolvedErrorPaths, ['lib/a.dart']);
      expect(stored.unresolvedErrorDiagnostics, hasLength(1));
      expect(stored.unverifiedChangePaths, ['lib/b.dart']);
      expect(stored.boundedToolLoopExhausted, isTrue);
      expect(stored.hasFailedExecutionVerification, isTrue);
      expect(stored.hasAuthoritativeDiagnosticSnapshot, isTrue);
      expect(stored.hasUnexecutedActionClaim, isTrue);
      expect(stored.diagnosticSignature, 'signature-a');
      expect(
        () => stored.unexecutedToolNames.add('late'),
        throwsUnsupportedError,
      );
      expect(
        () => stored.unresolvedErrorPaths.add('late'),
        throwsUnsupportedError,
      );
      expect(
        () => stored.unresolvedErrorDiagnostics.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => stored.unverifiedChangePaths.add('late'),
        throwsUnsupportedError,
      );

      final snapshot = fixture.registry.read(owner)!;
      expect(
        () => snapshot.replayedMutationGenerations.add(9),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.replayedInteractionGenerations.add(9),
        throwsUnsupportedError,
      );
    });

    test('keeps budget notice durable across tracker removal until reset', () {
      final ownerA = _owner('conversation-a');
      final ownerANext = _owner('conversation-a', generation: 2);
      final fixture = _Fixture();
      fixture.registry.create(ownerA);

      expect(fixture.registry.markBudgetNoticePresented(ownerA), isTrue);
      expect(fixture.registry.markBudgetNoticePresented(ownerANext), isFalse);
      expect(fixture.registry.read(ownerA)?.budgetNoticePresented, isTrue);

      fixture.registry.removeTracker(ownerA);
      expect(fixture.registry.read(ownerA), isNull);
      expect(fixture.registry.create(ownerA).budgetNoticePresented, isTrue);

      fixture.registry.resetConversation('conversation-a');
      expect(fixture.registry.read(ownerA), isNull);
      expect(fixture.registry.create(ownerA).budgetNoticePresented, isFalse);
      expect(fixture.registry.markBudgetNoticePresented(ownerA), isTrue);
    });

    test(
      'resets one conversation without touching another, then clears all',
      () {
        final ownerA = _owner('conversation-a');
        final ownerB = _owner('conversation-b');
        final fixture = _Fixture();
        fixture.registry.update(ownerA, noProgressStreak: 3);
        fixture.registry.update(ownerB, noProgressStreak: 7);
        fixture.registry.markBudgetNoticePresented(ownerA);
        fixture.registry.markBudgetNoticePresented(ownerB);
        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(ownerA),
          toolCall: _command('verify-a', 'flutter test'),
        );
        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(ownerB),
          toolCall: _command('verify-b', 'flutter test'),
        );

        fixture.registry.resetConversation('conversation-a');

        expect(fixture.registry.read(ownerA), isNull);
        expect(
          fixture.registry.hasVerifierReplayCandidate(_context(ownerA)),
          isFalse,
        );
        expect(fixture.registry.read(ownerB)?.noProgressStreak, 7);
        expect(fixture.registry.read(ownerB)?.budgetNoticePresented, isTrue);
        expect(
          fixture.registry.hasVerifierReplayCandidate(_context(ownerB)),
          isTrue,
        );

        fixture.registry.resetConversation(null);

        expect(fixture.registry.read(ownerB), isNull);
        expect(
          fixture.registry.hasVerifierReplayCandidate(_context(ownerB)),
          isFalse,
        );
        expect(fixture.registry.create(ownerB).budgetNoticePresented, isFalse);
      },
    );
  });

  group('GoalAutoContinueTrackerRegistry diagnostics', () {
    test('ignores non-coding and non-authoritative observations exactly', () {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();
      final ignoredWorkspace = fixture.registry.recordCommandDiagnostic(
        context: _context(owner, workspaceMode: WorkspaceMode.chat),
        commandKey: 'verify',
        toolResult: _diagnosticResult(),
      );

      expect(ignoredWorkspace, isNull);
      expect(fixture.registry.read(owner), isNull);

      final ignoredEvidence = fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'verify',
        toolResult: ToolResultInfo(
          id: 'empty',
          name: 'local_execute_command',
          arguments: const {'command': 'flutter test'},
          result: jsonEncode({'exit_code': 1, 'diagnostics': const []}),
        ),
      );

      expect(ignoredEvidence, isNull);
      expect(fixture.registry.read(owner), isNotNull);
      expect(
        fixture.registry.commandDiagnosticRepairFocusFor(_context(owner)),
        isNull,
      );
      expect(
        fixture.registry.commandDiagnosticRepairFocusFor(
          _context(owner, workspaceMode: WorkspaceMode.chat),
        ),
        isNull,
      );
    });

    test('tracks same and changed signatures with exact focus activation', () {
      final owner = _owner('conversation-a', generation: 3);
      final fixture = _Fixture();

      final first = fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'verify',
        toolResult: _diagnosticResult(runRoot: '/tmp/run-a', line: 10),
      )!;
      final repeated = fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'verify',
        toolResult: _diagnosticResult(runRoot: '/tmp/run-b', line: 42),
      )!;
      final changed = fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'verify',
        toolResult: _diagnosticResult(
          runRoot: '/tmp/run-a',
          line: 10,
          code: 'unexpected_entrypoint',
          message: 'Remove the unexpected entrypoint.',
        ),
      )!;
      final otherCommand = fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'analyze',
        toolResult: _diagnosticResult(runRoot: '/tmp/run-a', line: 10),
      )!;

      expect(first.owner, owner);
      expect(first.commandKey, 'verify');
      expect(first.streak, 1);
      expect(first.signatureChanged, isFalse);
      expect(first.focusActivated, isTrue);
      expect(first.repairFocus.hasPathBackedDiagnostic, isTrue);
      expect(
        first.repairFocus.diagnosticSummary,
        contains(
          'bin/todo_cli.dart: [todo_cli_missing] '
          'The required entrypoint does not exist.',
        ),
      );
      expect(first.repairFocus.diagnosticSummary, isNot(contains('/tmp/')));
      expect(repeated.streak, 2);
      expect(repeated.signatureChanged, isFalse);
      expect(repeated.focusActivated, isFalse);
      expect(changed.streak, 1);
      expect(changed.signatureChanged, isTrue);
      expect(changed.focusActivated, isFalse);
      expect(otherCommand.streak, 1);
      expect(otherCommand.focusActivated, isTrue);
      expect(
        fixture.registry
            .read(owner)
            ?.activeCommandDiagnosticRepairFocus
            ?.commandKey,
        'analyze',
      );
    });

    test(
      'keeps focus conversation-durable but isolates other conversations',
      () {
        final ownerA = _owner('conversation-a', generation: 3);
        final ownerANext = _owner('conversation-a', generation: 4);
        final ownerB = _owner('conversation-b', generation: 3);
        final fixture = _Fixture();
        fixture.registry.recordCommandDiagnostic(
          context: _context(ownerA),
          commandKey: 'verify',
          toolResult: _diagnosticResult(),
        );

        final sameConversation = fixture.registry
            .commandDiagnosticRepairFocusFor(_context(ownerANext));
        final foreign = fixture.registry.commandDiagnosticRepairFocusFor(
          _context(ownerB),
        );

        expect(sameConversation?.commandKey, 'verify');
        expect(sameConversation?.streak, 1);
        expect(foreign, isNull);
        expect(
          fixture.registry.clearCommandDiagnosticRepairFocus(ownerB),
          isFalse,
        );
        expect(
          fixture.registry.commandDiagnosticRepairFocusFor(_context(ownerA)),
          isNotNull,
        );
        expect(
          fixture.registry.clearCommandDiagnosticRepairFocus(ownerANext),
          isTrue,
        );
        expect(
          fixture.registry.clearCommandDiagnosticRepairFocus(ownerA),
          isFalse,
        );
      },
    );

    test('resets command streaks independently and clears matching focus', () {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();
      fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'verify',
        toolResult: _diagnosticResult(),
      );
      fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'analyze',
        toolResult: _diagnosticResult(),
      );

      expect(
        fixture.registry.resetCommandDiagnostic(owner, 'verify'),
        isFalse,
        reason: 'the active focus belongs to analyze',
      );
      final resetVerify = fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'verify',
        toolResult: _diagnosticResult(),
      )!;
      expect(resetVerify.streak, 1);
      expect(resetVerify.focusActivated, isTrue);
      expect(fixture.registry.resetCommandDiagnostic(owner, 'verify'), isTrue);
      expect(
        fixture.registry.commandDiagnosticRepairFocusFor(_context(owner)),
        isNull,
      );
      final retainedAnalyze = fixture.registry.recordCommandDiagnostic(
        context: _context(owner),
        commandKey: 'analyze',
        toolResult: _diagnosticResult(),
      )!;
      expect(retainedAnalyze.streak, 2);
      expect(
        fixture.registry.resetCommandDiagnostic(
          _owner('missing-conversation'),
          'verify',
        ),
        isFalse,
      );
    });
  });

  group('GoalAutoContinueTrackerRegistry verifier eligibility', () {
    test('preserves the complete syntactic eligibility matrix', () {
      final registry = _Fixture().registry;
      final cases = <(ToolCallInfo, bool)>[
        (
          _call('run', 'run_tests', arguments: const {'background': true}),
          true,
        ),
        (_call('run-case', ' RUN_TESTS '), true),
        (_command('safe', 'flutter test'), true),
        (_command('verify-script', 'dart run tool/verify.dart'), true),
        (_command('background', 'flutter test', background: true), false),
        (_command('missing', ''), false),
        (_command('space', '   '), false),
        (_command('newline', 'flutter test\npwd'), false),
        (_command('semicolon', 'flutter test; pwd'), false),
        (_command('ampersand', 'flutter test && pwd'), false),
        (_command('pipe', 'flutter test | tee out'), false),
        (_command('backtick', 'flutter test `pwd`'), false),
        (_command('less-than', 'flutter test < input'), false),
        (_command('greater-than', 'flutter test > out'), false),
        (_command('substitution', r'flutter test $(pwd)'), false),
        (_call('other', 'read_file'), false),
      ];

      for (final testCase in cases) {
        expect(
          registry.isReplayEligibleVerifierToolCall(testCase.$1),
          testCase.$2,
          reason: testCase.$1.id,
        );
      }
    });

    test('preserves invalid command casts and exact priority rules', () {
      final registry = _Fixture().registry;
      final invalid = _call(
        'invalid',
        'local_execute_command',
        arguments: const {'command': 7},
      );

      expect(
        () => registry.isReplayEligibleVerifierToolCall(invalid),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => registry.verifierReplayPriority(invalid),
        throwsA(isA<TypeError>()),
      );
      expect(registry.verifierReplayPriority(_call('run', 'run_tests')), 2);
      expect(
        registry.verifierReplayPriority(_call('run-case', ' RUN_TESTS ')),
        2,
      );
      expect(
        registry.verifierReplayPriority(_command('test', 'flutter test')),
        1,
      );
      expect(
        registry.verifierReplayPriority(
          _command('verify', 'dart run tool/verify.dart'),
        ),
        2,
      );
      expect(
        registry.verifierReplayPriority(
          _command('verifier', 'python tool_verifier.py'),
        ),
        2,
      );
    });

    test('requires command-effect verification and coding workspace', () {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();
      final formatting = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner),
        toolCall: _command('format', 'dart format .'),
      );
      final mutation = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner),
        toolCall: _command('echo', 'echo hello'),
      );
      final nonCoding = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner, workspaceMode: WorkspaceMode.chat),
        toolCall: _command('test', 'flutter test'),
      );

      for (final event in [formatting, mutation, nonCoding]) {
        expect(
          event.disposition,
          GoalVerifierReplayCandidateDisposition.ignored,
        );
        expect(event.taskChanged, isFalse);
        expect(event.priority, 0);
        expect(event.candidate, isNull);
      }
      expect(fixture.registry.read(owner), isNull);
    });
  });

  group('GoalAutoContinueTrackerRegistry verifier candidates', () {
    test('preserves priority, equal replacement, and task-change reset', () {
      final owner = _owner('conversation-a', generation: 6);
      final fixture = _Fixture();
      final lowArguments = <String, dynamic>{
        'command': 'flutter test',
        'metadata': <String, dynamic>{
          'paths': <Object?>['test/a_test.dart'],
          'flags': <Object?>['focused'],
        },
      };
      final low = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner),
        toolCall: _call(
          'low-priority',
          'local_execute_command',
          arguments: lowArguments,
        ),
      );
      lowArguments['command'] = 'poisoned';
      ((lowArguments['metadata'] as Map<String, dynamic>)['paths']
              as List<Object?>)
          .add('poison.dart');
      ((lowArguments['metadata'] as Map<String, dynamic>)['flags']
              as List<Object?>)
          .add('poisoned');

      expect(low.disposition, GoalVerifierReplayCandidateDisposition.recorded);
      expect(low.taskChanged, isTrue);
      expect(low.priority, 1);
      expect(low.candidate?.id, 'low-priority');
      expect(low.candidate?.taskId, 'task-a');
      expect(low.candidate?.arguments, {
        'command': 'flutter test',
        'metadata': {
          'paths': ['test/a_test.dart'],
          'flags': ['focused'],
        },
      });
      expect(
        () => low.candidate!.arguments['late'] = true,
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((low.candidate!.arguments['metadata']
                        as Map<String, dynamic>)['paths']
                    as List<Object?>)
                .add('late'),
        throwsUnsupportedError,
      );

      final high = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner),
        toolCall: _call('high-priority', 'run_tests'),
      );
      final retained = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner),
        toolCall: _command('later-low', 'flutter test'),
      );
      final equalReplacement = fixture.registry
          .recordExecutedVerifierReplayCandidate(
            context: _context(owner),
            toolCall: _call('equal-high', 'run_tests'),
          );

      expect(high.priority, 2);
      expect(high.candidate?.id, 'high-priority');
      expect(
        retained.disposition,
        GoalVerifierReplayCandidateDisposition.retainedHigherPriority,
      );
      expect(retained.candidate?.id, 'high-priority');
      expect(
        equalReplacement.disposition,
        GoalVerifierReplayCandidateDisposition.recorded,
      );
      expect(equalReplacement.candidate?.id, 'equal-high');

      final taskChanged = fixture.registry
          .recordExecutedVerifierReplayCandidate(
            context: _context(owner, activeTaskId: '  task-b  '),
            toolCall: _command('new-task-low', 'flutter test'),
          );
      expect(taskChanged.taskChanged, isTrue);
      expect(taskChanged.priority, 1);
      expect(taskChanged.candidate?.id, 'new-task-low');
      expect(taskChanged.candidate?.taskId, 'task-b');
      expect(
        fixture.registry.hasVerifierReplayCandidate(
          _context(owner, activeTaskId: 'task-a'),
        ),
        isFalse,
      );
      expect(
        fixture.registry.hasVerifierReplayCandidate(
          _context(owner, activeTaskId: ' task-b '),
        ),
        isTrue,
      );
    });

    test('rejects non-JSON verifier arguments before storing a candidate', () {
      final owner = _owner('conversation-a');
      final invalidValues = <Object?>[
        <Object?, Object?>{7: 'invalid'},
        <Object?>{'not-json'},
        Object(),
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final invalidValue in invalidValues) {
        final fixture = _Fixture();
        expect(
          () => fixture.registry.recordExecutedVerifierReplayCandidate(
            context: _context(owner),
            toolCall: _call(
              'invalid',
              'local_execute_command',
              arguments: {'command': 'flutter test', 'metadata': invalidValue},
            ),
          ),
          throwsArgumentError,
          reason: invalidValue.toString(),
        );
        expect(fixture.registry.read(owner)?.verifierReplayCandidate, isNull);
      }
    });

    test('keeps null task identity and resets when a task appears', () {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();

      final noTask = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner, activeTaskId: null),
        toolCall: _command('no-task', 'flutter test'),
      );
      final newTask = fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner, activeTaskId: 'task-a'),
        toolCall: _command('new-task', 'flutter test'),
      );

      expect(noTask.taskChanged, isFalse);
      expect(noTask.candidate?.taskId, isNull);
      expect(newTask.taskChanged, isTrue);
      expect(newTask.candidate?.taskId, 'task-a');
    });

    test(
      'keeps a candidate across generations without poisoning conversations',
      () {
        final ownerA = _owner('conversation-a', generation: 8);
        final ownerB = _owner('conversation-b', generation: 8);
        final ownerANext = _owner('conversation-a', generation: 9);
        final fixture = _Fixture();
        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(ownerA),
          toolCall: _call('owner-a', 'run_tests'),
        );

        expect(
          fixture.registry.hasVerifierReplayCandidate(_context(ownerA)),
          isTrue,
        );
        expect(
          fixture.registry.hasVerifierReplayCandidate(_context(ownerB)),
          isFalse,
        );
        expect(
          fixture.registry.hasVerifierReplayCandidate(_context(ownerANext)),
          isTrue,
        );
        expect(
          fixture.registry.read(ownerA)?.verifierReplayCandidate?.id,
          'owner-a',
        );
        expect(fixture.registry.read(ownerB), isNull);
        expect(
          fixture.registry.read(ownerANext)?.verifierReplayCandidate?.id,
          'owner-a',
        );

        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(ownerB),
          toolCall: _call('owner-b', 'run_tests'),
        );
        final retainedAcrossGeneration = fixture.registry
            .recordExecutedVerifierReplayCandidate(
              context: _context(ownerANext),
              toolCall: _command('owner-a-next', 'flutter test'),
            );

        expect(
          retainedAcrossGeneration.disposition,
          GoalVerifierReplayCandidateDisposition.retainedHigherPriority,
        );
        expect(
          fixture.registry.read(ownerA)?.verifierReplayCandidate?.id,
          'owner-a',
        );
        expect(
          fixture.registry.read(ownerB)?.verifierReplayCandidate?.id,
          'owner-b',
        );
        expect(
          fixture.registry.read(ownerANext)?.verifierReplayCandidate?.id,
          'owner-a',
        );
      },
    );

    test(
      'resets durable candidate priority on a next-generation task change',
      () {
        final owner = _owner('conversation-a', generation: 8);
        final ownerNext = _owner('conversation-a', generation: 9);
        final fixture = _Fixture();
        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(owner, activeTaskId: 'task-a'),
          toolCall: _call('task-a-high', 'run_tests'),
        );

        final changed = fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(ownerNext, activeTaskId: 'task-b'),
          toolCall: _command('task-b-low', 'flutter test'),
        );

        expect(changed.taskChanged, isTrue);
        expect(
          changed.disposition,
          GoalVerifierReplayCandidateDisposition.recorded,
        );
        expect(changed.priority, 1);
        expect(changed.candidate?.id, 'task-b-low');
        expect(
          fixture.registry.hasVerifierReplayCandidate(
            _context(owner, activeTaskId: 'task-a'),
          ),
          isFalse,
        );
        expect(
          fixture.registry.hasVerifierReplayCandidate(
            _context(ownerNext, activeTaskId: 'task-b'),
          ),
          isTrue,
        );
        expect(
          fixture.registry.read(owner)?.verifierReplayCandidate?.taskId,
          'task-b',
        );
      },
    );
  });

  group('GoalAutoContinueTrackerRegistry verifier replay', () {
    test('rejects every pre-selection generation and context gate', () {
      final owner = _owner('conversation-a', generation: 4);
      final fixture = _Fixture();
      fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner),
        toolCall: _command('candidate', 'flutter test'),
      );

      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(owner),
          evidence: const ToolResultCompletionEvidence(),
        ),
        isNull,
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(owner, workspaceMode: WorkspaceMode.chat),
          evidence: _mutationEvidence(),
        ),
        isNull,
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            owner,
            mutationGeneration: 2,
            verificationGeneration: 2,
          ),
          evidence: _mutationEvidence(),
        ),
        isNull,
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            owner,
            mutationGeneration: 2,
            verificationGeneration: 3,
          ),
          evidence: _mutationEvidence(),
        ),
        isNull,
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(owner, activeTaskId: 'task-b'),
          evidence: _mutationEvidence(),
        ),
        isNull,
      );
      expect(fixture.replayIdGenerations, isEmpty);

      final noCandidate = _Fixture();
      expect(
        noCandidate.registry.takePostMutationVerifierReplay(
          context: _context(owner),
          evidence: _mutationEvidence(),
        ),
        isNull,
      );
      expect(noCandidate.replayIdGenerations, isEmpty);
    });

    test('selects once with deterministic ID and defensive payload', () {
      final owner = _owner('conversation-a', generation: 4);
      final fixture = _Fixture();
      final nested = <String, dynamic>{
        'paths': <Object?>['test/a_test.dart'],
        'labels': <String, dynamic>{'owner': 'owner-a'},
      };
      final arguments = <String, dynamic>{
        'command': 'flutter test',
        'nested': nested,
      };
      fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner),
        toolCall: _call(
          'original-verifier',
          'local_execute_command',
          arguments: arguments,
        ),
      );
      arguments['command'] = 'poisoned';
      (nested['paths'] as List<Object?>).add('poison.dart');
      (nested['labels'] as Map)['owner'] = 'visible';

      final selection = fixture.registry.takePostMutationVerifierReplay(
        context: _context(
          owner,
          mutationGeneration: 6,
          verificationGeneration: 5,
        ),
        evidence: _mutationEvidence(),
      )!;

      expect(selection.owner, owner);
      expect(selection.mutationGeneration, 6);
      expect(selection.taskId, 'task-a');
      expect(selection.priority, 1);
      expect(selection.toolCall.id, 'post_mutation_verifier_6_fixed_1');
      expect(selection.toolCall.name, 'local_execute_command');
      expect(selection.toolCall.arguments, {
        'command': 'flutter test',
        'nested': {
          'paths': ['test/a_test.dart'],
          'labels': {'owner': 'owner-a'},
        },
      });
      expect(fixture.replayIdGenerations, [6]);
      expect(
        () => selection.toolCall.arguments['late'] = true,
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((selection.toolCall.arguments['nested']
                        as Map<String, dynamic>)['paths']
                    as List<Object?>)
                .add('late'),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((selection.toolCall.arguments['nested']
                        as Map<String, dynamic>)['labels']
                    as Map)['owner'] =
                'late',
        throwsUnsupportedError,
      );

      final snapshot = fixture.registry.read(owner)!;
      expect(snapshot.replayedMutationGenerations, {6});
      expect(snapshot.replayedInteractionGenerations, {4});
      expect(
        () => snapshot.replayedMutationGenerations.add(7),
        throwsUnsupportedError,
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            owner,
            mutationGeneration: 6,
            verificationGeneration: 5,
          ),
          evidence: _mutationEvidence(),
        ),
        isNull,
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            owner,
            mutationGeneration: 7,
            verificationGeneration: 6,
          ),
          evidence: _mutationEvidence(),
        ),
        isNull,
        reason: 'one interaction generation can replay only once',
      );
      expect(fixture.replayIdGenerations, [6]);
    });

    test(
      'shares mutation replay-once across generations but not conversations',
      () {
        final ownerA = _owner('conversation-a', generation: 4);
        final ownerANext = _owner('conversation-a', generation: 5);
        final ownerB = _owner('conversation-b', generation: 4);
        final fixture = _Fixture();

        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(ownerA),
          toolCall: _command('owner-a-first', 'flutter test'),
        );
        final first = fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            ownerA,
            mutationGeneration: 6,
            verificationGeneration: 5,
          ),
          evidence: _mutationEvidence(),
        );
        expect(first, isNotNull);

        final repeatedMutation = fixture.registry
            .takePostMutationVerifierReplay(
              context: _context(
                ownerANext,
                mutationGeneration: 6,
                verificationGeneration: 5,
              ),
              evidence: _mutationEvidence(),
            );
        final advancedMutation = fixture.registry
            .takePostMutationVerifierReplay(
              context: _context(
                ownerANext,
                mutationGeneration: 7,
                verificationGeneration: 6,
              ),
              evidence: _mutationEvidence(),
            );

        expect(repeatedMutation, isNull);
        expect(
          advancedMutation?.toolCall.id,
          'post_mutation_verifier_7_fixed_2',
        );
        expect(advancedMutation?.toolCall.id, isNot(first?.toolCall.id));
        expect(advancedMutation?.toolCall.name, 'local_execute_command');
        expect(advancedMutation?.toolCall.arguments['command'], 'flutter test');

        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(ownerB),
          toolCall: _command('owner-b', 'flutter test'),
        );
        final foreignConversation = fixture.registry
            .takePostMutationVerifierReplay(
              context: _context(
                ownerB,
                mutationGeneration: 6,
                verificationGeneration: 5,
              ),
              evidence: _mutationEvidence(),
            );

        expect(
          foreignConversation?.toolCall.id,
          'post_mutation_verifier_6_fixed_3',
        );
        expect(fixture.registry.read(ownerA)?.replayedMutationGenerations, {
          6,
          7,
        });
        expect(fixture.registry.read(ownerA)?.replayedInteractionGenerations, {
          4,
        });
        expect(
          fixture.registry.read(ownerANext)?.replayedInteractionGenerations,
          {5},
        );
        expect(fixture.registry.read(ownerB)?.replayedMutationGenerations, {6});
        expect(fixture.registry.read(ownerB)?.replayedInteractionGenerations, {
          4,
        });
      },
    );

    test('task changes do not clear replay-once state', () {
      final owner = _owner('conversation-a', generation: 2);
      final fixture = _Fixture();
      fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner, activeTaskId: 'task-a'),
        toolCall: _command('task-a', 'flutter test'),
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            owner,
            activeTaskId: 'task-a',
            mutationGeneration: 3,
            verificationGeneration: 2,
          ),
          evidence: _mutationEvidence(),
        ),
        isNotNull,
      );

      fixture.registry.recordExecutedVerifierReplayCandidate(
        context: _context(owner, activeTaskId: 'task-b'),
        toolCall: _command('task-b', 'flutter test'),
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            owner,
            activeTaskId: 'task-b',
            mutationGeneration: 3,
            verificationGeneration: 2,
          ),
          evidence: _mutationEvidence(),
        ),
        isNull,
      );
      expect(
        fixture.registry.takePostMutationVerifierReplay(
          context: _context(
            owner,
            activeTaskId: 'task-b',
            mutationGeneration: 4,
            verificationGeneration: 3,
          ),
          evidence: _mutationEvidence(),
        ),
        isNull,
        reason: 'the interaction-generation replay was already spent',
      );
    });

    test('tracker removal clears every owner replay for the conversation', () {
      final owner = _owner('conversation-a', generation: 2);
      final ownerNext = _owner('conversation-a', generation: 3);
      final fixture = _Fixture();
      for (final current in [owner, ownerNext]) {
        fixture.registry.recordExecutedVerifierReplayCandidate(
          context: _context(current),
          toolCall: _command(
            'candidate-${current.interactionGeneration}',
            'flutter test',
          ),
        );
      }

      fixture.registry.removeTracker(owner);

      expect(fixture.registry.read(owner), isNull);
      expect(
        fixture.registry.hasVerifierReplayCandidate(_context(owner)),
        isFalse,
      );
      expect(
        fixture.registry.hasVerifierReplayCandidate(_context(ownerNext)),
        isFalse,
      );
    });
  });
}

final class _Fixture {
  _Fixture() {
    registry = GoalAutoContinueTrackerRegistry(
      replayIdFactory: (mutationGeneration) {
        replayIdGenerations.add(mutationGeneration);
        return 'post_mutation_verifier_${mutationGeneration}_'
            'fixed_${replayIdGenerations.length}';
      },
    );
  }

  final List<int> replayIdGenerations = [];
  late final GoalAutoContinueTrackerRegistry registry;
}

ToolResultInfo _diagnosticResult({
  String runRoot = '/tmp/run-a',
  int line = 10,
  String code = 'todo_cli_missing',
  String message = 'The required entrypoint does not exist.',
}) {
  final path = '$runRoot/bin/todo_cli.dart';
  return ToolResultInfo(
    id: 'verify-$line',
    name: 'local_execute_command',
    arguments: const {'command': 'dart run tool/verify.dart'},
    result: jsonEncode({
      'exit_code': 1,
      'diagnostics': [
        {
          'severity': 'Error',
          'path': path,
          'relative_path': 'bin/todo_cli.dart',
          'line': line,
          'column': 1,
          'code': code,
          'message': '$message at $path:$line:1',
        },
      ],
    }),
  );
}
