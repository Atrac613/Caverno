import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_task_readiness.dart';
import 'package:test/test.dart';

const _resolver = ConversationTaskReadinessResolver();

const _blocked = ConversationWorkflowTask(
  id: 'build-sync',
  title: 'Build the sync engine',
  preconditions: [
    ConversationTaskPrecondition(
      kind: ConversationTaskPreconditionKind.task,
      ref: 'inspect-model',
    ),
    ConversationTaskPrecondition(
      kind: ConversationTaskPreconditionKind.assumption,
      ref: 'constraint:stable-entity-ids',
    ),
    ConversationTaskPrecondition(
      kind: ConversationTaskPreconditionKind.question,
      ref: 'Which conflict policy applies?',
    ),
  ],
);

Conversation _conversation({
  List<ConversationWorkflowTask> tasks = const [],
  List<ConversationContractItemProvenance> provenance = const [],
  List<ConversationOpenQuestionProgress> questions = const [],
  List<ConversationExecutionTaskProgress> progress = const [],
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Decomposition',
    messages: const <Message>[],
    createdAt: DateTime(2026, 9, 4),
    updatedAt: DateTime(2026, 9, 4),
    workflowSpec: ConversationWorkflowSpec(
      goal: 'Add iCloud synchronization',
      constraints: const ['Existing entities have stable UUIDs'],
      openQuestions: const ['Which conflict policy applies?'],
      tasks: [_blocked, ...tasks],
      provenance: provenance,
    ),
    openQuestionProgress: questions,
    executionProgress: progress,
  );
}

ConversationWorkflowTask _dependency({
  ConversationWorkflowTaskStatus status =
      ConversationWorkflowTaskStatus.pending,
  String validationCommand = '',
}) {
  return ConversationWorkflowTask(
    id: 'inspect-model',
    title: 'Inspect the data model',
    status: status,
    validationCommand: validationCommand,
  );
}

const _confirmedAssumption = ConversationContractItemProvenance(
  itemId: 'constraint:stable-entity-ids',
  kind: ConversationContractItemKind.constraint,
  assumption: true,
  material: true,
  confirmed: true,
);

const _resolvedQuestion = ConversationOpenQuestionProgress(
  questionId: 'question-1',
  question: 'Which conflict policy applies?',
  status: ConversationOpenQuestionStatus.resolved,
);

void main() {
  group('a task waits on all three shapes', () {
    test('nothing satisfied leaves every edge unmet', () {
      final readiness = _resolver.resolve(
        _conversation(tasks: [_dependency()]),
        _blocked,
      );

      expect(readiness.isReady, isFalse);
      expect(readiness.unmet, hasLength(3));
      expect(
        readiness.unmet.map((item) => item.kind),
        containsAll(ConversationTaskPreconditionKind.values),
        reason:
            'A dependency list would have expressed one of these. The '
            'other two are what make the epistemic model load-bearing rather '
            'than decorative.',
      );
    });

    test('satisfying all three makes it ready', () {
      final readiness = _resolver.resolve(
        _conversation(
          tasks: [
            _dependency(status: ConversationWorkflowTaskStatus.completed),
          ],
          provenance: const [_confirmedAssumption],
          questions: const [_resolvedQuestion],
        ),
        _blocked,
      );

      expect(readiness.isReady, isTrue);
      expect(readiness.unmet, isEmpty);
    });

    test('an unconfirmed assumption alone holds the task', () {
      final readiness = _resolver.resolve(
        _conversation(
          tasks: [
            _dependency(status: ConversationWorkflowTaskStatus.completed),
          ],
          provenance: const [
            ConversationContractItemProvenance(
              itemId: 'constraint:stable-entity-ids',
              kind: ConversationContractItemKind.constraint,
              assumption: true,
              material: true,
            ),
          ],
          questions: const [_resolvedQuestion],
        ),
        _blocked,
      );

      expect(readiness.isReady, isFalse);
      expect(
        readiness.unmet.single.kind,
        ConversationTaskPreconditionKind.assumption,
      );
    });

    test('a deferred question is not a resolved one', () {
      final readiness = _resolver.resolve(
        _conversation(
          tasks: [
            _dependency(status: ConversationWorkflowTaskStatus.completed),
          ],
          provenance: const [_confirmedAssumption],
          questions: const [
            ConversationOpenQuestionProgress(
              questionId: 'question-1',
              question: 'Which conflict policy applies?',
              status: ConversationOpenQuestionStatus.deferred,
            ),
          ],
        ),
        _blocked,
      );

      expect(
        readiness.unmet.single.kind,
        ConversationTaskPreconditionKind.question,
      );
    });
  });

  group('a finished task means evidence, not a claim', () {
    ConversationTaskReadiness readinessFor({
      required String validationCommand,
      ConversationExecutionValidationStatus? validationStatus,
    }) {
      return _resolver.resolve(
        _conversation(
          tasks: [
            _dependency(
              status: ConversationWorkflowTaskStatus.completed,
              validationCommand: validationCommand,
            ),
          ],
          progress: [
            if (validationStatus != null)
              ConversationExecutionTaskProgress(
                taskId: 'inspect-model',
                status: ConversationWorkflowTaskStatus.completed,
                validationStatus: validationStatus,
              ),
          ],
          provenance: const [_confirmedAssumption],
          questions: const [_resolvedQuestion],
        ),
        _blocked,
      );
    }

    test('a task with no validation command is taken at its status', () {
      expect(readinessFor(validationCommand: '').isReady, isTrue);
    });

    test('a declared validation command must actually have passed', () {
      expect(
        readinessFor(
          validationCommand: 'dart test',
          validationStatus: ConversationExecutionValidationStatus.unknown,
        ).isReady,
        isFalse,
        reason:
            'completed conflates produced, verified and accepted until '
            'ANA3 separates them, so the strongest existing evidence stands in '
            'for acceptance. Reading the lenient of two notions of "verified" '
            'is a mistake this codebase has already paid for.',
      );
      expect(
        readinessFor(
          validationCommand: 'dart test',
          validationStatus: ConversationExecutionValidationStatus.passed,
        ).isReady,
        isTrue,
      );
    });
  });

  group('edges that point nowhere', () {
    test('an unknown reference is unmet, never vacuously satisfied', () {
      for (final kind in ConversationTaskPreconditionKind.values) {
        final readiness = _resolver.resolve(
          _conversation(),
          ConversationWorkflowTask(
            id: 'orphan',
            title: 'Orphan',
            preconditions: [
              ConversationTaskPrecondition(kind: kind, ref: 'does-not-exist'),
            ],
          ),
        );

        expect(
          readiness.isReady,
          isFalse,
          reason:
              '${kind.name}: a plan that names something absent must not '
              'run the work it said depended on it.',
        );
      }
    });

    test('a blank reference is unmet', () {
      final readiness = _resolver.resolve(
        _conversation(),
        const ConversationWorkflowTask(
          id: 'orphan',
          title: 'Orphan',
          preconditions: [
            ConversationTaskPrecondition(
              kind: ConversationTaskPreconditionKind.task,
              ref: '   ',
            ),
          ],
        ),
      );

      expect(readiness.isReady, isFalse);
    });
  });

  test('a task with no preconditions is ready', () {
    final readiness = _resolver.resolve(
      _conversation(),
      const ConversationWorkflowTask(id: 'free', title: 'Free'),
    );

    expect(readiness.isReady, isTrue);
  });

  test('resolveAll keys every task in the contract', () {
    final readiness = _resolver.resolveAll(
      _conversation(tasks: [_dependency()]),
    );

    expect(
      readiness.keys,
      containsAll(<String>['build-sync', 'inspect-model']),
    );
    expect(readiness['build-sync']!.isReady, isFalse);
    expect(readiness['inspect-model']!.isReady, isTrue);
  });
}
