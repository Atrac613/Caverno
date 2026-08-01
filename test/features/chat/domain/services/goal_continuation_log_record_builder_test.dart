import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_tracker_registry.dart';
import 'package:caverno/features/chat/domain/services/goal_continuation_log_record_builder.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/verification_cadence_policy.dart';
import 'package:test/test.dart';

const _builder = GoalContinuationLogRecordBuilder();

void main() {
  group('GoalContinuationLogRecordBuilder auto-continue records', () {
    test('omits nullable goal and tracker fields', () {
      final record = _builder.buildAutoContinue(
        owner: _owner('owner-a', 4),
        decision: 'skip',
        reason: 'no active goal',
        goal: null,
        nextTurnNumber: null,
        effectiveTurnBudget: null,
        tracker: null,
        evidence: const ToolResultCompletionEvidence(),
        verificationCadence: VerificationCadence.notDue,
        mutationGeneration: null,
        verificationGeneration: null,
        safeBoundary: _safeBoundary(),
      );

      expect(record.owner, _owner('owner-a', 4));
      expect(record.goalId, isNull);
      expect(record.consecutiveAutoContinuations, isNull);
      expect(record.payload.keys, ['decision', 'reason', 'evidence']);
      expect(record.payload, {
        'decision': 'skip',
        'reason': 'no active goal',
        'evidence': {
          'summary': 'no incomplete evidence',
          'hasIncompleteEvidence': false,
          'verificationCadence': 'notDue',
          'mutationGeneration': null,
          'verificationGeneration': null,
          'hasBlockingEvidence': false,
          'hasUnexecutedActionClaim': false,
          'safeBoundaryVeto': null,
          'noProgressStreak': 0,
          'hasVerifierReplayCandidate': false,
          'diagnosticRepairContinuations': 0,
          'consecutiveValidationMisses': 0,
          'diagnosticRepairExtensionUsed': false,
          'previousUnresolvedErrorCount': null,
          'diagnosticSignaturePresent': false,
          'identicalDiagnosticSignatureStreak': 0,
          'boundedToolLoopExhausted': false,
          'unexecutedToolNames': <String>[],
          'unresolvedErrorCount': 0,
          'unresolvedErrorPaths': <String>[],
          'unverifiedChangePaths': <String>[],
          'mutatedWithoutExecution': false,
        },
      });
    });

    test(
      'builds every counter, cadence, generation, veto, and evidence field',
      () {
        final previousEvidence = const ToolResultCompletionEvidence(
          unresolvedErrorCount: 7,
        );
        final tracker = _tracker(
          consecutiveAutoContinuations: 3,
          diagnosticRepairContinuations: 2,
          diagnosticRepairExtensionUsed: true,
          noProgressStreak: 4,
          consecutiveValidationMisses: 5,
          previousEvidence: previousEvidence,
          identicalDiagnosticSignatureStreak: 6,
        );
        final evidence = ToolResultCompletionEvidence(
          boundedToolLoopExhausted: true,
          unexecutedToolNames: const ['run_tests'],
          unresolvedErrorCount: 2,
          unresolvedErrorPaths: const ['lib/a.dart'],
          unverifiedChangePaths: const ['lib/b.dart'],
          mutatedWithoutExecutionVerification: true,
          hasFailedExecutionVerification: true,
          hasUnexecutedActionClaim: true,
          diagnosticSignature: 'signature',
        );
        final record = _builder.buildAutoContinue(
          owner: _owner('owner-a', 9),
          decision: 'continue',
          reason: 'incomplete evidence remains',
          goal: _goal(id: '  goal-1  '),
          nextTurnNumber: 4,
          effectiveTurnBudget: 10,
          tracker: tracker,
          evidence: evidence,
          verificationCadence: VerificationCadence.required,
          mutationGeneration: 8,
          verificationGeneration: 6,
          safeBoundary: _safeBoundary(hasPendingAskUserQuestion: true),
        );

        expect(record.goalId, 'goal-1');
        expect(record.nextTurnNumber, 4);
        expect(record.effectiveTurnBudget, 10);
        expect(record.consecutiveAutoContinuations, 3);
        expect(record.evidence, {
          'summary':
              'execution verification failed; '
              '2 unresolved Error diagnostic(s) in lib/a.dart; '
              'bounded tool loop stopped before executing run_tests; '
              'unverified file change(s) in lib/b.dart; '
              'files were modified without execution-class verification; '
              'claimed file or command actions were not executed',
          'hasIncompleteEvidence': true,
          'verificationCadence': 'required',
          'mutationGeneration': 8,
          'verificationGeneration': 6,
          'hasBlockingEvidence': true,
          'hasUnexecutedActionClaim': true,
          'safeBoundaryVeto': 'assistant question is pending',
          'noProgressStreak': 4,
          'hasVerifierReplayCandidate': false,
          'diagnosticRepairContinuations': 2,
          'consecutiveValidationMisses': 5,
          'diagnosticRepairExtensionUsed': true,
          'previousUnresolvedErrorCount': 7,
          'diagnosticSignaturePresent': true,
          'identicalDiagnosticSignatureStreak': 6,
          'boundedToolLoopExhausted': true,
          'unexecutedToolNames': ['run_tests'],
          'unresolvedErrorCount': 2,
          'unresolvedErrorPaths': ['lib/a.dart'],
          'unverifiedChangePaths': ['lib/b.dart'],
          'mutatedWithoutExecution': true,
        });
        expect(record.payload, {
          'decision': 'continue',
          'reason': 'incomplete evidence remains',
          'goalId': 'goal-1',
          'nextTurnNumber': 4,
          'effectiveTurnBudget': 10,
          'consecutiveAutoContinuations': 3,
          'evidence': record.evidence,
        });
      },
    );

    test('preserves every current decision label and reason exactly', () {
      for (final decision in [
        'continue',
        'skip',
        'stop_and_block',
        'budget_stop',
        'no_progress_stop',
      ]) {
        final record = _builder.buildAutoContinue(
          owner: _owner('owner-a', 1),
          decision: decision,
          reason: ' reason for $decision ',
          goal: _goal(),
          nextTurnNumber: 1,
          effectiveTurnBudget: 10,
          tracker: _tracker(),
          evidence: const ToolResultCompletionEvidence(),
          verificationCadence: VerificationCadence.due,
          mutationGeneration: 1,
          verificationGeneration: -1,
          safeBoundary: _safeBoundary(),
        );

        expect(record.decision, decision);
        expect(record.reason, ' reason for $decision ');
      }
    });

    test('an empty normalized goal id is omitted', () {
      final record = _builder.buildAutoContinue(
        owner: _owner('owner-a', 1),
        decision: 'skip',
        reason: 'reason',
        goal: _goal(id: ' \n '),
        nextTurnNumber: null,
        effectiveTurnBudget: null,
        tracker: null,
        evidence: const ToolResultCompletionEvidence(),
        verificationCadence: VerificationCadence.notDue,
        mutationGeneration: 0,
        verificationGeneration: -1,
        safeBoundary: _safeBoundary(),
      );

      expect(record.goalId, isNull);
      expect(record.payload, isNot(contains('goalId')));
    });

    test('freezes owner evidence and generations for delayed writes', () {
      final unexecuted = <String>['run_tests'];
      final paths = <String>['lib/owner-a.dart'];
      final owner = _owner('owner-a', 12);
      final record = _builder.buildAutoContinue(
        owner: owner,
        decision: 'continue',
        reason: 'owner A reason',
        goal: _goal(),
        nextTurnNumber: 2,
        effectiveTurnBudget: 10,
        tracker: _tracker(),
        evidence: ToolResultCompletionEvidence(
          boundedToolLoopExhausted: true,
          unexecutedToolNames: unexecuted,
          unresolvedErrorCount: 1,
          unresolvedErrorPaths: paths,
        ),
        verificationCadence: VerificationCadence.required,
        mutationGeneration: 5,
        verificationGeneration: 3,
        safeBoundary: _safeBoundary(),
      );
      final visibleOwnerRecord = _builder.buildAutoContinue(
        owner: _owner('visible-b', 44),
        decision: 'skip',
        reason: 'visible owner reason',
        goal: _goal(id: 'visible-goal'),
        nextTurnNumber: 9,
        effectiveTurnBudget: 99,
        tracker: _tracker(consecutiveAutoContinuations: 8),
        evidence: const ToolResultCompletionEvidence(),
        verificationCadence: VerificationCadence.notDue,
        mutationGeneration: 91,
        verificationGeneration: 90,
        safeBoundary: _safeBoundary(),
      );
      unexecuted[0] = 'visible_owner_tool';
      paths[0] = 'lib/visible-b.dart';

      expect(record.owner, owner);
      expect(record.owner, isNot(visibleOwnerRecord.owner));
      expect(record.goalId, 'goal-1');
      expect(record.nextTurnNumber, 2);
      expect(record.effectiveTurnBudget, 10);
      expect(record.consecutiveAutoContinuations, 0);
      expect(record.evidence['verificationCadence'], 'required');
      expect(record.evidence['mutationGeneration'], 5);
      expect(record.evidence['verificationGeneration'], 3);
      expect(record.evidence['unexecutedToolNames'], ['run_tests']);
      expect(record.evidence['unresolvedErrorPaths'], ['lib/owner-a.dart']);
      expect(
        () => record.evidence['summary'] = 'mutated',
        throwsUnsupportedError,
      );
      expect(
        () => (record.evidence['unexecutedToolNames'] as List<Object?>).add(
          'mutation',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => record.payload['decision'] = 'mutated',
        throwsUnsupportedError,
      );
    });
  });

  group('GoalContinuationLogRecordBuilder shadow records', () {
    test('builds every disagreement with the exact stable label', () {
      final cases =
          <
            ({
              GoalUpdateAckOutcome? outcome,
              bool lexicalCompleted,
              String label,
              String? toolOutcome,
            })
          >[
            (
              outcome: GoalUpdateAckOutcome.completionRecorded,
              lexicalCompleted: false,
              label: 'goal_completion_tool_accepted_lexical_missed',
              toolOutcome: 'completionRecorded',
            ),
            (
              outcome: GoalUpdateAckOutcome.completionRejected,
              lexicalCompleted: true,
              label: 'goal_completion_tool_rejected_lexical_completed',
              toolOutcome: 'completionRejected',
            ),
            (
              outcome: null,
              lexicalCompleted: true,
              label: 'goal_completion_lexical_only',
              toolOutcome: null,
            ),
            (
              outcome: GoalUpdateAckOutcome.progressLogged,
              lexicalCompleted: true,
              label: 'goal_completion_lexical_only',
              toolOutcome: 'progressLogged',
            ),
          ];

      for (final testCase in cases) {
        final record = _builder.buildCompletionShadow(
          owner: _owner('owner-a', 23),
          lexicalCompleted: testCase.lexicalCompleted,
          toolCompletionOutcome: testCase.outcome,
        );

        expect(record, isNotNull);
        expect(record!.owner, _owner('owner-a', 23));
        expect(record.label, testCase.label);
        expect(record.toolOutcome, testCase.toolOutcome);
        expect(record.lexicalCompleted, testCase.lexicalCompleted);
        expect(record.turnId, 'gen-23');
        expect(record.payload, {
          'label': testCase.label,
          if (testCase.toolOutcome != null) 'toolOutcome': testCase.toolOutcome,
          'lexicalCompleted': testCase.lexicalCompleted,
          'turnId': 'gen-23',
        });
      }
    });

    test('omits the null tool outcome from the shadow payload', () {
      final record = _builder.buildCompletionShadow(
        owner: _owner('owner-a', 5),
        lexicalCompleted: true,
        toolCompletionOutcome: null,
      );

      expect(record!.payload, {
        'label': 'goal_completion_lexical_only',
        'lexicalCompleted': true,
        'turnId': 'gen-5',
      });
    });

    test('returns no record for every agreeing outcome', () {
      final cases = <({GoalUpdateAckOutcome? outcome, bool lexicalCompleted})>[
        (
          outcome: GoalUpdateAckOutcome.completionRecorded,
          lexicalCompleted: true,
        ),
        (
          outcome: GoalUpdateAckOutcome.completionRejected,
          lexicalCompleted: false,
        ),
        (outcome: null, lexicalCompleted: false),
        (outcome: GoalUpdateAckOutcome.blockerLogged, lexicalCompleted: false),
      ];

      for (final testCase in cases) {
        expect(
          _builder.buildCompletionShadow(
            owner: _owner('owner-a', 1),
            lexicalCompleted: testCase.lexicalCompleted,
            toolCompletionOutcome: testCase.outcome,
          ),
          isNull,
        );
      }
    });

    test('retains the captured owner when another turn becomes visible', () {
      final capturedOwner = _owner('owner-a', 31);
      final record = _builder.buildCompletionShadow(
        owner: capturedOwner,
        lexicalCompleted: false,
        toolCompletionOutcome: GoalUpdateAckOutcome.completionRecorded,
      );
      final visibleOwner = _owner('visible-b', 44);

      expect(record!.owner, capturedOwner);
      expect(record.owner, isNot(visibleOwner));
      expect(record.turnId, 'gen-31');
    });
  });
}

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

ConversationGoal _goal({String id = 'goal-1'}) {
  final timestamp = DateTime.utc(2026, 7, 31);
  return ConversationGoal(
    id: id,
    objective: 'Finish the task',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

GoalAutoContinueTrackerSnapshot _tracker({
  int consecutiveAutoContinuations = 0,
  int diagnosticRepairContinuations = 0,
  bool diagnosticRepairExtensionUsed = false,
  int noProgressStreak = 0,
  int consecutiveValidationMisses = 0,
  ToolResultCompletionEvidence? previousEvidence,
  int identicalDiagnosticSignatureStreak = 0,
}) => (
  consecutiveAutoContinuations: consecutiveAutoContinuations,
  diagnosticRepairContinuations: diagnosticRepairContinuations,
  diagnosticRepairExtensionUsed: diagnosticRepairExtensionUsed,
  noProgressStreak: noProgressStreak,
  consecutiveValidationMisses: consecutiveValidationMisses,
  failedVerificationObserved: false,
  previousEvidence: previousEvidence,
  previousDiagnosticSignature: '',
  identicalDiagnosticSignatureStreak: identicalDiagnosticSignatureStreak,
  pendingPostRepairReplayOutcome: false,
  pendingRepairContractOutcome: false,
  repairNoMutationRetryUsed: false,
  completionElicitationMutationGeneration: null,
  activeCommandDiagnosticRepairFocus: null,
  verifierReplayCandidate: null,
  replayedMutationGenerations: const <int>{},
  replayedInteractionGenerations: const <int>{},
  budgetNoticePresented: false,
);

GoalAutoContinueSafeBoundary _safeBoundary({
  bool hasPendingAskUserQuestion = false,
}) => GoalAutoContinueSafeBoundary(
  isLoading: false,
  hasQueuedUserInput: false,
  hasPendingSshConnect: false,
  hasPendingSshCommand: false,
  hasPendingGitCommand: false,
  hasPendingLocalCommand: false,
  hasPendingComputerUseAction: false,
  hasPendingBrowserAction: false,
  hasPendingFileOperation: false,
  hasPendingBleConnect: false,
  hasPendingSerialOpen: false,
  hasPendingParticipantToolApproval: false,
  hasPendingAskUserQuestion: hasPendingAskUserQuestion,
  hasPendingWorkflowDecision: false,
  hasParticipantTurnRuntime: false,
  hasError: false,
);
