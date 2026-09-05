import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/task_delegation_brief_builder.dart';
import 'package:test/test.dart';

const _builder = TaskDelegationBriefBuilder();
const _provenance = ConversationContractProvenanceService();

const _confirmedClaim = 'Existing entities have stable UUIDs';
const _openClaim = 'The archive fits in memory';

String _idFor(String value) => _provenance.itemId(
  kind: ConversationContractItemKind.constraint,
  value: value,
);

ConversationWorkflowTask _task({
  required String id,
  required String title,
  List<ConversationTaskPrecondition> preconditions = const [],
  ConversationWorkflowTaskStatus status =
      ConversationWorkflowTaskStatus.pending,
  List<String> targetFiles = const [],
  String validationCommand = '',
}) {
  return ConversationWorkflowTask(
    id: id,
    title: title,
    status: status,
    preconditions: preconditions,
    targetFiles: targetFiles,
    validationCommand: validationCommand,
  );
}

Conversation _conversation({
  required List<ConversationWorkflowTask> tasks,
  bool confirmFirst = true,
  bool confirmSecond = false,
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Delegation',
    messages: const <Message>[],
    createdAt: DateTime(2026, 9, 4),
    updatedAt: DateTime(2026, 9, 4),
    workflowSpec: ConversationWorkflowSpec(
      goal: 'Add iCloud synchronization',
      constraints: const [_confirmedClaim, _openClaim],
      tasks: tasks,
      provenance: [
        ConversationContractItemProvenance(
          itemId: _idFor(_confirmedClaim),
          kind: ConversationContractItemKind.constraint,
          assumption: true,
          material: true,
          confirmed: confirmFirst,
        ),
        ConversationContractItemProvenance(
          itemId: _idFor(_openClaim),
          kind: ConversationContractItemKind.constraint,
          assumption: true,
          material: true,
          confirmed: confirmSecond,
        ),
      ],
    ),
  );
}

void main() {
  group('what may be delegated', () {
    test('a ready task is a candidate', () {
      final briefs = _builder.candidates(
        _conversation(
          tasks: [_task(id: 'free', title: 'Do the thing')],
        ),
      );

      expect(briefs.map((brief) => brief.task.id), ['free']);
    });

    test('a task still waiting on something is not', () {
      final briefs = _builder.candidates(
        _conversation(
          tasks: [
            _task(
              id: 'blocked-by-assumption',
              title: 'Write the sync engine',
              preconditions: [
                ConversationTaskPrecondition(
                  kind: ConversationTaskPreconditionKind.assumption,
                  ref: _idFor(_openClaim),
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        briefs,
        isEmpty,
        reason:
            'Delegating a task whose premise nobody has confirmed hands the '
            'guess to a child that cannot check it.',
      );
    });

    test('work already finished or running is not offered again', () {
      for (final status in [
        ConversationWorkflowTaskStatus.inProgress,
        ConversationWorkflowTaskStatus.completed,
        ConversationWorkflowTaskStatus.blocked,
      ]) {
        expect(
          _builder.candidates(
            _conversation(
              tasks: [_task(id: 'busy', title: 'Do it', status: status)],
            ),
          ),
          isEmpty,
          reason: status.name,
        );
      }
    });

    test('recorded progress outranks the authored status', () {
      final conversation =
          _conversation(
            tasks: [_task(id: 'authored-pending', title: 'Do it')],
          ).copyWith(
            executionProgress: const [
              ConversationExecutionTaskProgress(
                taskId: 'authored-pending',
                status: ConversationWorkflowTaskStatus.inProgress,
              ),
            ],
          );

      expect(
        _builder.candidates(conversation),
        isEmpty,
        reason:
            'Nothing writes completion back to the authored status, so reading '
            'it alone would offer running work to a second child.',
      );
    });
  });

  group('what the child is told', () {
    test('only the premises this task stands on', () {
      final briefs = _builder.candidates(
        _conversation(
          tasks: [
            _task(
              id: 'sync',
              title: 'Write the sync engine',
              preconditions: [
                ConversationTaskPrecondition(
                  kind: ConversationTaskPreconditionKind.assumption,
                  ref: _idFor(_confirmedClaim),
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        briefs.single.premises,
        [_confirmedClaim],
        reason:
            'A child cannot see the conversation, so its prompt is the only '
            'channel — and the edge is what makes it possible to send the one '
            'assumption that matters instead of the whole contract.',
      );
      expect(
        briefs.single.premises,
        isNot(contains(_openClaim)),
        reason:
            'An assumption this task does not depend on is not its premise.',
      );
    });

    test('a task with no assumption edge carries no premises', () {
      final briefs = _builder.candidates(
        _conversation(
          tasks: [
            _task(
              id: 'audit',
              title: 'Audit the data model',
              preconditions: [
                ConversationTaskPrecondition(
                  kind: ConversationTaskPreconditionKind.question,
                  ref: 'Which policy?',
                ),
              ],
            ),
          ],
          confirmFirst: true,
        ),
      );

      // The question edge is unmet, so this is not a candidate at all; the
      // point is that a met question does not become a premise either.
      expect(briefs, isEmpty);
    });

    test('an edge pointing at a dropped item does not invent a premise', () {
      final briefs = _builder.candidates(
        _conversation(
          tasks: [
            _task(
              id: 'sync',
              title: 'Write the sync engine',
              preconditions: [
                ConversationTaskPrecondition(
                  kind: ConversationTaskPreconditionKind.assumption,
                  ref: 'constraint:edited-away',
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        briefs,
        isEmpty,
        reason:
            'An edge naming nothing is unmet, so the task is held rather than '
            'delegated with a premise nobody can read.',
      );
    });
  });

  group('where the work runs', () {
    TaskDelegationRunner runnerFor({
      List<String> targetFiles = const [],
      String validationCommand = '',
    }) {
      return _builder
          .candidates(
            _conversation(
              tasks: [
                _task(
                  id: 'task-1',
                  title: 'Do it',
                  targetFiles: targetFiles,
                  validationCommand: validationCommand,
                ),
              ],
            ),
          )
          .single
          .runner;
    }

    test('a task that declares files to change goes to a worktree', () {
      expect(
        runnerFor(targetFiles: const ['lib/sync/engine.dart']),
        TaskDelegationRunner.worktree,
      );
    });

    test('a task that declares a validation command goes to a worktree', () {
      expect(
        runnerFor(validationCommand: 'dart test'),
        TaskDelegationRunner.worktree,
      );
    });

    test('a task declaring neither goes to a subagent', () {
      expect(
        runnerFor(),
        TaskDelegationRunner.subagent,
        reason:
            'Nothing to change and nothing to verify is the only case where a '
            'summary is the whole result.',
      );
    });

    test('a blank declaration is not a declaration', () {
      expect(
        runnerFor(targetFiles: const ['  '], validationCommand: '   '),
        TaskDelegationRunner.subagent,
      );
    });

    test('the router fails toward isolation', () {
      // Two subagents editing one workspace corrupt each other and neither
      // leaves evidence to accept on; a worktree spent on inspection costs one
      // worktree. Only one of those errors is recoverable.
      expect(
        runnerFor(targetFiles: const ['lib/a.dart'], validationCommand: 'x'),
        TaskDelegationRunner.worktree,
      );
      expect(
        _builder.runnerFor(
          const ConversationWorkflowTask(id: 'x', title: 'Investigate'),
        ),
        TaskDelegationRunner.subagent,
      );
    });
  });

  group('the shape a real plan actually carries', () {
    // Every fixture above builds its refs with _idFor, and every one of them
    // passed while no real edge could resolve: the planning prompt asks for the
    // constraint's own text, and an item id is a hash of that text.
    test('a premise named by its text reaches the child', () {
      final task = _task(
        id: 'f498f1f9-900b-427b-b3bf-269bab08e359',
        title: 'Implement the counter',
        targetFiles: const ['jsonl_count.py'],
        preconditions: const [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.assumption,
            ref: _confirmedClaim,
          ),
        ],
      );

      final briefs = _builder.candidates(_conversation(tasks: [task]));

      expect(
        briefs.single.premises,
        [_confirmedClaim],
        reason:
            'A child that cannot see the conversation is told only what its '
            'task stands on. An unresolvable ref left that list empty, so the '
            'premise silently turned back into a guess one level down.',
      );
    });

    test('an unconfirmed premise named by its text keeps the task out', () {
      final task = _task(
        id: 'f498f1f9-900b-427b-b3bf-269bab08e359',
        title: 'Implement the counter',
        targetFiles: const ['jsonl_count.py'],
        preconditions: const [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.assumption,
            ref: _openClaim,
          ),
        ],
      );

      final briefs = _builder.candidates(_conversation(tasks: [task]));

      expect(
        briefs,
        isEmpty,
        reason:
            'An unconfirmed assumption is an unmet edge, so the task never '
            'becomes a candidate. Delegating it with the premise merely '
            'omitted would hand a child work resting on something nobody '
            'established.',
      );
    });
  });
}
