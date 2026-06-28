import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_protocol.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RemoteCodingQuestion survives a JSON round-trip', () {
    const question = RemoteCodingQuestion(
      id: 'question-1',
      question: 'Which version?',
      help: 'Pick one.',
      options: [
        RemoteCodingQuestionOption(
          id: 'opt-a',
          label: 'A',
          description: 'first',
          preview: 'pa',
        ),
        RemoteCodingQuestionOption(id: 'opt-b', label: 'B'),
      ],
      allowMultiple: true,
      allowOther: false,
      otherPlaceholder: 'custom',
    );

    final decoded = RemoteCodingQuestion.fromJson(question.toJson());
    expect(decoded.id, question.id);
    expect(decoded.question, question.question);
    expect(decoded.help, question.help);
    expect(decoded.options.length, 2);
    expect(decoded.options.first.id, 'opt-a');
    expect(decoded.options.first.description, 'first');
    expect(decoded.options.first.preview, 'pa');
    expect(decoded.allowMultiple, isTrue);
    expect(decoded.allowOther, isFalse);
    expect(decoded.otherPlaceholder, 'custom');
  });

  test('copyWith can clear stale remote selection IDs', () {
    const state = RemoteCodingClientState(
      selectedProjectId: 'project-1',
      currentConversationId: 'thread-1',
    );

    final next = state.copyWith(
      clearSelectedProjectId: true,
      clearCurrentConversationId: true,
    );

    expect(next.selectedProjectId, isNull);
    expect(next.currentConversationId, isNull);
  });

  test('copyWith can clear scheduled reconnect metadata', () {
    final state = RemoteCodingClientState(
      reconnectAttempt: 2,
      nextReconnectAt: DateTime(2026, 5, 26, 12),
      pendingCommandCount: 1,
    );

    final next = state.copyWith(
      reconnectAttempt: 0,
      pendingCommandCount: 0,
      clearNextReconnectAt: true,
    );

    expect(next.reconnectAttempt, 0);
    expect(next.nextReconnectAt, isNull);
    expect(next.pendingCommandCount, 0);
    expect(next.hasScheduledReconnect, isFalse);
  });

  group('snapshot application', () {
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'restores project, thread, messages, loading, and approval state',
      () async {
        final notifier = container.read(remoteCodingClientProvider.notifier);
        final message = Message(
          id: 'message-1',
          content: 'Remote answer',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 5, 26, 12),
        );

        await notifier.applySnapshotForTest({
          'snapshotSequence': 7,
          'snapshotGeneratedAt': DateTime(
            2026,
            5,
            26,
            12,
            30,
          ).toIso8601String(),
          'projects': [
            {'id': 'project-1', 'name': 'App', 'rootPath': '/tmp/app'},
          ],
          'selectedProjectId': 'project-1',
          'conversations': [
            {
              'id': 'thread-1',
              'title': 'Fix crash',
              'projectId': 'project-1',
              'updatedAt': DateTime(2026, 5, 26, 12).toIso8601String(),
            },
          ],
          'currentConversationId': 'thread-1',
          'messages': [message.toJson()],
          'isLoading': true,
          'queuedCount': 2,
          'pendingApproval': {
            'id': 'approval-1',
            'kind': 'localCommand',
            'title': 'Local Command Approval',
            'subtitle': '/tmp/app',
            'detail': 'dart test',
          },
        });

        final state = container.read(remoteCodingClientProvider);
        expect(state.status, RemoteCodingConnectionStatus.connected);
        expect(state.snapshotSequence, 7);
        expect(state.snapshotGeneratedAt, DateTime(2026, 5, 26, 12, 30));
        expect(state.projects.single.id, 'project-1');
        expect(state.selectedProjectId, 'project-1');
        expect(state.threads.single.id, 'thread-1');
        expect(state.currentConversationId, 'thread-1');
        expect(state.messages.single.content, 'Remote answer');
        expect(state.isLoading, isTrue);
        expect(state.queuedCount, 2);
        expect(state.pendingApproval?.id, 'approval-1');
      },
    );

    test('restores and clears pending ask_user_question state', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);

      await notifier.applySnapshotForTest({
        'snapshotSequence': 3,
        'isLoading': false,
        'pendingQuestion': {
          'id': 'question-1',
          'question': 'Which version?',
          'help': 'Pick a release version.',
          'options': [
            {'id': 'opt-bump', 'label': '1.3.11+22', 'description': 'Bump'},
            {'id': 'opt-keep', 'label': '1.3.2+13'},
          ],
          'allowMultiple': false,
          'allowOther': true,
          'otherPlaceholder': 'Custom version',
        },
      });

      final question = container.read(remoteCodingClientProvider).pendingQuestion;
      expect(question?.id, 'question-1');
      expect(question?.question, 'Which version?');
      expect(question?.options.length, 2);
      expect(question?.options.first.id, 'opt-bump');
      expect(question?.allowMultiple, isFalse);
      expect(question?.allowOther, isTrue);
      expect(question?.otherPlaceholder, 'Custom version');

      // A later snapshot without the question (it was answered) clears it.
      await notifier.applySnapshotForTest({
        'snapshotSequence': 4,
        'isLoading': false,
      });
      expect(
        container.read(remoteCodingClientProvider).pendingQuestion,
        isNull,
      );
    });

    test(
      'ignores older snapshots after reconnect state has advanced',
      () async {
        final notifier = container.read(remoteCodingClientProvider.notifier);

        await notifier.applySnapshotForTest({
          'snapshotSequence': 5,
          'projects': [
            {'id': 'project-new', 'name': 'New', 'rootPath': '/tmp/new'},
          ],
          'selectedProjectId': 'project-new',
        });
        await notifier.applySnapshotForTest({
          'snapshotSequence': 4,
          'projects': [
            {'id': 'project-old', 'name': 'Old', 'rootPath': '/tmp/old'},
          ],
          'selectedProjectId': 'project-old',
        });

        final state = container.read(remoteCodingClientProvider);
        expect(state.snapshotSequence, 5);
        expect(state.projects.single.id, 'project-new');
        expect(state.selectedProjectId, 'project-new');
      },
    );

    test(
      'disconnect resets snapshot ordering and pending remote state',
      () async {
        final notifier = container.read(remoteCodingClientProvider.notifier);

        await notifier.applySnapshotForTest({
          'snapshotSequence': 7,
          'snapshotGeneratedAt': DateTime(
            2026,
            5,
            26,
            12,
            30,
          ).toIso8601String(),
          'projects': [
            {'id': 'project-old', 'name': 'Old', 'rootPath': '/tmp/old'},
          ],
          'selectedProjectId': 'project-old',
          'isLoading': true,
          'queuedCount': 1,
          'pendingApproval': {
            'id': 'approval-1',
            'kind': 'gitCommand',
            'title': 'Git Command Approval',
            'subtitle': '/tmp/old',
            'detail': 'git checkout -b branch',
          },
        });

        await notifier.disconnect();
        var state = container.read(remoteCodingClientProvider);
        expect(state.status, RemoteCodingConnectionStatus.disconnected);
        expect(state.snapshotSequence, 0);
        expect(state.snapshotGeneratedAt, isNull);
        expect(state.isLoading, isFalse);
        expect(state.queuedCount, 0);
        expect(state.pendingApproval, isNull);

        await notifier.applySnapshotForTest({
          'snapshotSequence': 1,
          'projects': [
            {'id': 'project-new', 'name': 'New', 'rootPath': '/tmp/new'},
          ],
          'selectedProjectId': 'project-new',
        });

        state = container.read(remoteCodingClientProvider);
        expect(state.status, RemoteCodingConnectionStatus.connected);
        expect(state.snapshotSequence, 1);
        expect(state.projects.single.id, 'project-new');
        expect(state.selectedProjectId, 'project-new');
      },
    );

    test('rejects unsupported server events', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);

      await notifier.handleRawMessageForTest(
        RemoteCodingProtocol.encode(
          type: 'unknownEvent',
          payload: const <String, dynamic>{},
        ),
      );

      final state = container.read(remoteCodingClientProvider);
      expect(state.status, RemoteCodingConnectionStatus.error);
      expect(state.error, 'Unsupported remote coding event: unknownEvent');
      expect(state.snapshotSequence, 0);
      expect(state.pendingApproval, isNull);
      expect(state.snapshotGeneratedAt, isNull);
    });
  });

  group('remote host rejection', () {
    late SharedPreferences prefs;
    late _FakeRemoteCodingRepository repository;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repository = _FakeRemoteCodingRepository(
        prefs,
        RemoteCodingHost(
          id: 'device-1',
          name: 'Desktop',
          host: '192.168.1.10',
          port: 8767,
          createdAt: DateTime(2026, 5, 26, 12),
          updatedAt: DateTime(2026, 5, 26, 12),
        ),
      );
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteCodingRepositoryProvider.overrideWithValue(repository),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('unauthorized token clears the saved mobile host', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);

      await notifier.handleRawMessageForTest(
        RemoteCodingProtocol.encode(
          type: 'error',
          payload: const {
            'code': 'unauthorized',
            'message': 'Remote coding token was not recognized.',
          },
        ),
      );

      final state = container.read(remoteCodingClientProvider);
      expect(repository.clearCount, 1);
      expect(repository.host, isNull);
      expect(state.status, RemoteCodingConnectionStatus.error);
      expect(state.host, isNull);
      expect(state.error, contains('Pair with the desktop again'));
    });

    test('revoked disconnect clears the saved mobile host', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);

      await notifier.handleRawMessageForTest(
        RemoteCodingProtocol.encode(
          type: 'disconnected',
          payload: const {'reason': 'revoked'},
        ),
      );

      final state = container.read(remoteCodingClientProvider);
      expect(repository.clearCount, 1);
      expect(repository.host, isNull);
      expect(state.status, RemoteCodingConnectionStatus.error);
      expect(state.host, isNull);
      expect(state.error, contains('revoked on the desktop'));
    });

    test('missing saved token gives pairing recovery guidance', () async {
      repository.token = null;
      final notifier = container.read(remoteCodingClientProvider.notifier);

      await notifier.connectSavedHost();

      final state = container.read(remoteCodingClientProvider);
      expect(state.status, RemoteCodingConnectionStatus.disconnected);
      expect(state.error, contains('Saved credentials'));
      expect(state.error, contains('fresh device token'));
    });

    test('unexpected disconnect schedules a bounded reconnect attempt', () {
      final notifier = container.read(remoteCodingClientProvider.notifier);

      notifier.handleUnexpectedDisconnectForTest('Connection closed.');

      final state = container.read(remoteCodingClientProvider);
      expect(state.status, RemoteCodingConnectionStatus.disconnected);
      expect(state.reconnectAttempt, 1);
      expect(state.nextReconnectAt, isNotNull);
      expect(state.hasScheduledReconnect, isTrue);
      expect(state.pendingCommandCount, 0);
      expect(state.error, contains('Reconnecting'));
    });

    test('manual disconnect clears scheduled reconnect metadata', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);

      notifier.handleUnexpectedDisconnectForTest('Connection closed.');
      await notifier.disconnect();

      final state = container.read(remoteCodingClientProvider);
      expect(state.status, RemoteCodingConnectionStatus.disconnected);
      expect(state.reconnectAttempt, 0);
      expect(state.nextReconnectAt, isNull);
      expect(state.hasScheduledReconnect, isFalse);
    });
  });

  group('pairing QR validation', () {
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('invalid QR data gives desktop QR recovery guidance', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);

      await notifier.pairFromQr('not-json');

      final state = container.read(remoteCodingClientProvider);
      expect(state.status, RemoteCodingConnectionStatus.error);
      expect(state.error, contains('not a Caverno Remote Coding pairing code'));
      expect(state.error, contains('fresh pairing QR'));
    });

    test('expired QR data explains the 5 minute pairing window', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);
      final payload = RemoteCodingPairingPayload(
        ticketId: 'ticket-1',
        secret: 'secret',
        host: '192.168.1.10',
        port: 8767,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        serverName: 'Desktop',
      );

      await notifier.pairFromQr(payload.toQrData());

      final state = container.read(remoteCodingClientProvider);
      expect(state.status, RemoteCodingConnectionStatus.error);
      expect(state.error, contains('expired'));
      expect(state.error, contains('5 minutes'));
    });

    test('non-LAN QR data is rejected before connecting', () async {
      final notifier = container.read(remoteCodingClientProvider.notifier);
      final payload = RemoteCodingPairingPayload(
        ticketId: 'ticket-1',
        secret: 'secret',
        host: '8.8.8.8',
        port: 8767,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        serverName: 'Desktop',
      );

      await notifier.pairFromQr(payload.toQrData());

      final state = container.read(remoteCodingClientProvider);
      expect(state.status, RemoteCodingConnectionStatus.error);
      expect(state.error, contains('LAN address'));
      expect(state.error, contains('same local network'));
    });
  });
}

class _FakeRemoteCodingRepository extends RemoteCodingRepository {
  _FakeRemoteCodingRepository(super.prefs, this.host);

  RemoteCodingHost? host;
  String? token = 'token';
  int clearCount = 0;

  @override
  RemoteCodingHost? loadMobileHost() => host;

  @override
  Future<void> saveMobileHost(RemoteCodingHost host, String token) async {
    this.host = host;
  }

  @override
  Future<String?> loadMobileHostToken(String hostId) async => token;

  @override
  Future<void> clearMobileHost() async {
    clearCount += 1;
    host = null;
  }
}
