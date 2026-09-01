import 'dart:async';

import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/pending_approval_summary.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/pending_approval_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatTurnOwner owner(String conversationId) =>
      ChatTurnOwner(conversationId: conversationId, interactionGeneration: 1);

  PendingLocalCommand localCommand({
    required String conversationId,
    required String id,
    String? remoteDeviceId,
  }) => PendingLocalCommand(
    owner: owner(conversationId),
    id: id,
    command: 'dart analyze',
    workingDirectory: '/repo',
    reason: 'Inspect diagnostics.',
    warningTitle: null,
    warningMessage: null,
    completer: Completer<LocalCommandApproval>(),
    origin: remoteDeviceId == null
        ? ChatInteractionOrigin.local
        : ChatInteractionOrigin.remote,
    remoteDeviceId: remoteDeviceId,
  );

  group('findPendingApprovalSummary', () {
    test('finds the approval registered for the requested thread', () {
      final registry = PendingToolApprovalRegistry()
        ..register(localCommand(conversationId: 'thread-a', id: 'a-1'))
        ..register(localCommand(conversationId: 'thread-b', id: 'b-1'));

      final summary = findPendingApprovalSummary(
        registry,
        conversationId: 'thread-b',
      );

      expect(summary, isNotNull);
      expect(summary!.id, 'b-1');
      expect(summary.conversationId, 'thread-b');
    });

    test('skips an approval owned by a paired remote device (SEC4.5g)', () {
      final registry = PendingToolApprovalRegistry()
        ..register(
          localCommand(
            conversationId: 'thread-a',
            id: 'remote-1',
            remoteDeviceId: 'device-b',
          ),
        );

      expect(
        findPendingApprovalSummary(registry, conversationId: 'thread-a'),
        isNull,
        reason:
            'That approval belongs to the paired device that started the '
            'turn; this device must not answer it.',
      );
    });

    test(
      'falls through a remote-owned approval to a local one on the same thread',
      () {
        final registry = PendingToolApprovalRegistry()
          ..register(
            localCommand(
              conversationId: 'thread-a',
              id: 'remote-1',
              remoteDeviceId: 'device-b',
            ),
          )
          ..register(
            PendingGitCommand(
              owner: owner('thread-a'),
              id: 'local-git',
              command: 'git status',
              workingDirectory: '/repo',
              reason: null,
              completer: Completer<bool>(),
            ),
          );

        final summary = findPendingApprovalSummary(
          registry,
          conversationId: 'thread-a',
        );

        expect(summary!.id, 'local-git');
        expect(summary.kind, PendingApprovalKinds.gitCommand);
      },
    );

    test('returns null when the thread has nothing pending', () {
      final registry = PendingToolApprovalRegistry()
        ..register(localCommand(conversationId: 'thread-a', id: 'a-1'));

      expect(
        findPendingApprovalSummary(registry, conversationId: 'thread-z'),
        isNull,
      );
    });

    test('an empty registry yields null', () {
      expect(
        findPendingApprovalSummary(
          PendingToolApprovalRegistry(),
          conversationId: 'thread-a',
        ),
        isNull,
      );
    });
  });

  group('showPendingApprovalNotification', () {
    test('names the command and offers a decision for a simple kind', () async {
      final notifications = _RecordingNotificationService();
      final registry = PendingToolApprovalRegistry()
        ..register(localCommand(conversationId: 'thread-a', id: 'a-1'));

      await showPendingApprovalNotification(
        notifications,
        conversationId: 'thread-a',
        threadTitle: 'Fix the parser',
        summary: findPendingApprovalSummary(
          registry,
          conversationId: 'thread-a',
        ),
      );

      final call = notifications.calls.single;
      expect(call.title, 'Fix the parser');
      expect(call.body, 'Fix the parser wants to run: dart analyze.');
      expect(call.approvalId, 'a-1');
      expect(call.allowsDirectDecision, isTrue);
    });

    test('withholds the decision when the kind needs structured input',
        () async {
      final notifications = _RecordingNotificationService();
      final registry = PendingToolApprovalRegistry()
        ..register(
          PendingSshConnect(
            owner: owner('thread-a'),
            id: 'ssh-1',
            host: 'example.internal',
            port: 22,
            username: 'deploy',
            savedCredential: null,
            identityCandidates: const [],
            completer: Completer<SshConnectApproval?>(),
          ),
        );

      await showPendingApprovalNotification(
        notifications,
        conversationId: 'thread-a',
        threadTitle: 'Deploy',
        summary: findPendingApprovalSummary(
          registry,
          conversationId: 'thread-a',
        ),
      );

      expect(
        notifications.calls.single.allowsDirectDecision,
        isFalse,
        reason:
            'An Approve button cannot stand in for the credentials this '
            'request actually needs.',
      );
    });

    test('falls back to a generic body when nothing is described', () async {
      final notifications = _RecordingNotificationService();

      await showPendingApprovalNotification(
        notifications,
        conversationId: 'thread-a',
        threadTitle: '',
        summary: null,
      );

      final call = notifications.calls.single;
      expect(call.title, 'Caverno');
      expect(call.body, 'A thread is waiting for your approval.');
      expect(call.approvalId, isNull);
      expect(
        call.allowsDirectDecision,
        isFalse,
        reason: 'Without an id the decision could land on the wrong request.',
      );
    });
  });
}

/// Captures what `showPendingApprovalNotification` asked for, without touching
/// the platform plugin.
class _RecordingNotificationService extends NotificationService {
  final List<
    ({
      String conversationId,
      String title,
      String body,
      String? approvalId,
      bool allowsDirectDecision,
    })
  >
  calls = [];

  @override
  Future<void> showApprovalRequiredNotification({
    required String conversationId,
    required String title,
    required String body,
    String? approvalId,
    bool allowsDirectDecision = false,
  }) async {
    calls.add((
      conversationId: conversationId,
      title: title,
      body: body,
      approvalId: approvalId,
      allowsDirectDecision: allowsDirectDecision,
    ));
  }
}
