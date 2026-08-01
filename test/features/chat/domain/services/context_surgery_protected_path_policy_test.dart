import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/context_surgery_protected_path_policy.dart';
import 'package:test/test.dart';

const _policy = ContextSurgeryProtectedPathPolicy();
final _timestamp = DateTime.utc(2026, 7, 31, 12);

Conversation _conversation({
  String id = 'conversation-a',
  List<ConversationWorkflowTask> tasks = const [],
  List<ConversationExecutionTaskProgress> progress = const [],
}) => Conversation(
  id: id,
  title: id,
  messages: const [],
  createdAt: _timestamp,
  updatedAt: _timestamp,
  workflowSpec: ConversationWorkflowSpec(tasks: tasks),
  executionProgress: progress,
);

ConversationWorkflowTask _task(
  String id,
  ConversationWorkflowTaskStatus status, {
  List<String> targetFiles = const [],
}) => ConversationWorkflowTask(
  id: id,
  title: id,
  status: status,
  targetFiles: targetFiles,
);

void main() {
  group('ContextSurgeryProtectedPathPolicy', () {
    test('returns an immutable empty set for a null conversation', () {
      final paths = _policy.protectedPathsFor(null);

      expect(paths, isEmpty);
      expect(() => paths.add('late.dart'), throwsUnsupportedError);
    });

    test('returns empty sets when no execution focus exists', () {
      final conversations = [
        _conversation(),
        _conversation(
          tasks: [
            _task(
              'completed',
              ConversationWorkflowTaskStatus.completed,
              targetFiles: const ['lib/completed.dart'],
            ),
          ],
        ),
      ];

      for (final conversation in conversations) {
        final paths = _policy.protectedPathsFor(conversation);

        expect(paths, isEmpty, reason: conversation.id);
        expect(() => paths.add('late.dart'), throwsUnsupportedError);
      }
    });

    test('trims, filters, deduplicates, and freezes focused paths', () {
      final sourcePaths = <String>[
        '  lib/main.dart  ',
        '',
        '   ',
        'lib/main.dart',
        'lib/Feature.dart',
        'lib/feature.dart',
        './test/main_test.dart',
      ];
      final conversation = _conversation(
        tasks: [
          _task(
            'active',
            ConversationWorkflowTaskStatus.inProgress,
            targetFiles: sourcePaths,
          ),
        ],
      );

      final paths = _policy.protectedPathsFor(conversation);
      sourcePaths
        ..clear()
        ..add('lib/poison.dart');

      expect(paths.toList(), [
        'lib/main.dart',
        'lib/Feature.dart',
        'lib/feature.dart',
        './test/main_test.dart',
      ]);
      expect(paths, isNot(contains('lib/poison.dart')));
      expect(() => paths.add('late.dart'), throwsUnsupportedError);
      expect(() => paths.remove('lib/main.dart'), throwsUnsupportedError);
    });

    test('returns immutable empty set for whitespace-only focused paths', () {
      final paths = _policy.protectedPathsFor(
        _conversation(
          tasks: [
            _task(
              'active',
              ConversationWorkflowTaskStatus.inProgress,
              targetFiles: const ['', ' ', '\n\t'],
            ),
          ],
        ),
      );

      expect(paths, isEmpty);
      expect(() => paths.add('late.dart'), throwsUnsupportedError);
    });

    test('does not fall through when the focused task has no usable paths', () {
      final paths = _policy.protectedPathsFor(
        _conversation(
          tasks: [
            _task(
              'blocked',
              ConversationWorkflowTaskStatus.blocked,
              targetFiles: const ['lib/blocked.dart'],
            ),
            _task(
              'active',
              ConversationWorkflowTaskStatus.inProgress,
              targetFiles: const [' ', ''],
            ),
            _task(
              'pending',
              ConversationWorkflowTaskStatus.pending,
              targetFiles: const ['lib/pending.dart'],
            ),
          ],
        ),
      );

      expect(paths, isEmpty);
    });

    test('prefers the first active task over blocked and pending tasks', () {
      final paths = _policy.protectedPathsFor(
        _conversation(
          tasks: [
            _task(
              'pending',
              ConversationWorkflowTaskStatus.pending,
              targetFiles: const ['lib/pending.dart'],
            ),
            _task(
              'blocked',
              ConversationWorkflowTaskStatus.blocked,
              targetFiles: const ['lib/blocked.dart'],
            ),
            _task(
              'active-first',
              ConversationWorkflowTaskStatus.inProgress,
              targetFiles: const ['lib/active_first.dart'],
            ),
            _task(
              'active-second',
              ConversationWorkflowTaskStatus.inProgress,
              targetFiles: const ['lib/active_second.dart'],
            ),
          ],
        ),
      );

      expect(paths, {'lib/active_first.dart'});
    });

    test('prefers the first blocked task when no task is active', () {
      final paths = _policy.protectedPathsFor(
        _conversation(
          tasks: [
            _task(
              'pending',
              ConversationWorkflowTaskStatus.pending,
              targetFiles: const ['lib/pending.dart'],
            ),
            _task(
              'blocked-first',
              ConversationWorkflowTaskStatus.blocked,
              targetFiles: const ['lib/blocked_first.dart'],
            ),
            _task(
              'blocked-second',
              ConversationWorkflowTaskStatus.blocked,
              targetFiles: const ['lib/blocked_second.dart'],
            ),
          ],
        ),
      );

      expect(paths, {'lib/blocked_first.dart'});
    });

    test(
      'selects the first pending task when nothing is active or blocked',
      () {
        final paths = _policy.protectedPathsFor(
          _conversation(
            tasks: [
              _task(
                'completed',
                ConversationWorkflowTaskStatus.completed,
                targetFiles: const ['lib/completed.dart'],
              ),
              _task(
                'pending-first',
                ConversationWorkflowTaskStatus.pending,
                targetFiles: const ['lib/pending_first.dart'],
              ),
              _task(
                'pending-second',
                ConversationWorkflowTaskStatus.pending,
                targetFiles: const ['lib/pending_second.dart'],
              ),
            ],
          ),
        );

        expect(paths, {'lib/pending_first.dart'});
      },
    );

    test('uses projected execution progress when selecting focus', () {
      final paths = _policy.protectedPathsFor(
        _conversation(
          tasks: [
            _task(
              'task-a',
              ConversationWorkflowTaskStatus.pending,
              targetFiles: const ['lib/task_a.dart'],
            ),
            _task(
              'task-b',
              ConversationWorkflowTaskStatus.pending,
              targetFiles: const ['lib/task_b.dart'],
            ),
          ],
          progress: const [
            ConversationExecutionTaskProgress(
              taskId: 'task-a',
              status: ConversationWorkflowTaskStatus.completed,
            ),
            ConversationExecutionTaskProgress(
              taskId: 'task-b',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );

      expect(paths, {'lib/task_b.dart'});
    });

    test('uses only the owning conversation, never visible-thread paths', () {
      final ownerConversation = _conversation(
        id: 'owner-conversation',
        tasks: [
          _task(
            'shared-task-id',
            ConversationWorkflowTaskStatus.inProgress,
            targetFiles: const [
              ' lib/owner_only.dart ',
              'test/owner_test.dart',
            ],
          ),
        ],
      );
      final visibleConversation = _conversation(
        id: 'visible-conversation',
        tasks: [
          _task(
            'shared-task-id',
            ConversationWorkflowTaskStatus.inProgress,
            targetFiles: const [
              'lib/visible_only.dart',
              'test/visible_test.dart',
            ],
          ),
        ],
      );

      final ownerPaths = _policy.protectedPathsFor(ownerConversation);
      final visiblePaths = _policy.protectedPathsFor(visibleConversation);

      expect(ownerPaths, {'lib/owner_only.dart', 'test/owner_test.dart'});
      expect(ownerPaths, isNot(contains('lib/visible_only.dart')));
      expect(ownerPaths, isNot(contains('test/visible_test.dart')));
      expect(visiblePaths, {'lib/visible_only.dart', 'test/visible_test.dart'});
      expect(visiblePaths, isNot(contains('lib/owner_only.dart')));
      expect(visiblePaths, isNot(contains('test/owner_test.dart')));
    });
  });
}
