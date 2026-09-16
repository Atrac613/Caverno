import 'dart:convert';

import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
import 'package:caverno/features/watch/domain/watch_command.dart';
import 'package:caverno/features/watch/domain/watch_snapshot.dart';
import 'package:caverno/features/watch/presentation/watch_remote_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RemoteCodingClientState remote;
  late WatchRemoteNavigation navigation;
  late List<String> selections;

  void update(RemoteCodingClientState next) {
    final previous = remote;
    remote = next;
    navigation.update(previous, next);
  }

  WatchCommand command(
    String type, {
    String? projectId,
    String? threadId,
    int offset = 0,
  }) {
    final browser = navigation.snapshot();
    return WatchCommand(
      id: 'tap-1',
      type: type,
      payload: {
        'hostId': browser.hostId,
        'sessionId': browser.sessionId,
        'projectId': ?projectId,
        'conversationId': ?threadId,
        'offset': offset,
        'source': 'remote',
      },
    );
  }

  setUp(() {
    remote = _remote();
    selections = [];
    navigation = WatchRemoteNavigation(
      readRemote: () => remote,
      selectConversation: (id) async {
        selections.add(id);
      },
      onChanged: () {},
      selectionTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(navigation.dispose);
  });

  test(
    'all projects and threads are reachable without selecting a desktop project',
    () async {
      final projectIds = <String>[];
      for (final offset in [0, 8, 16]) {
        final result = await navigation.handle(
          command(WatchCommand.browseRemote, offset: offset),
        );
        expect(result.ok, isTrue);
        projectIds.addAll(navigation.snapshot().items.map((p) => p.id));
      }
      expect(projectIds, remote.projects.map((p) => p.id));
      final threadIds = <String>[];
      for (final offset in [0, 8, 16]) {
        await navigation.handle(
          command(WatchCommand.browseRemote, projectId: 'p-16', offset: offset),
        );
        threadIds.addAll(navigation.snapshot().items.map((p) => p.id));
      }
      expect(threadIds, remote.threads.map((t) => t.id));
      expect(selections, isEmpty);
      expect(remote.selectedProjectId, 'p-0');
      expect(navigation.source, 'remote');
    },
  );

  test(
    'selection completes only after a newer matching host snapshot',
    () async {
      var completed = false;
      final pending = navigation
          .handle(
            command(
              WatchCommand.selectRemoteConversation,
              projectId: 'p-16',
              threadId: 't-16',
            ),
          )
          .then((result) {
            completed = true;
            return result;
          });
      expect(selections, ['t-16']);
      expect(navigation.snapshot().selectionStatus, 'selecting');
      update(
        remote.copyWith(
          snapshotSequence: 11,
          currentConversationId: 't-0',
          selectedProjectId: 'p-16',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      update(
        remote.copyWith(snapshotSequence: 12, currentConversationId: 't-16'),
      );
      expect((await pending).ok, isTrue);
      expect(navigation.snapshot().selectionStatus, 'selected');
      update(
        remote.copyWith(snapshotSequence: 13, currentConversationId: 't-0'),
      );
      expect(navigation.snapshot().selectionStatus, 'changed');
      expect(navigation.snapshot().conversationId, 't-16');
    },
  );

  test('wrong-project selection is refused before sending', () async {
    final result = await navigation.handle(
      command(
        WatchCommand.selectRemoteConversation,
        projectId: 'p-0',
        threadId: 't-16',
      ),
    );
    expect(result.code, 'conversation_not_found');
    expect(selections, isEmpty);
  });

  test('input stays bound to the confirmed connection and thread', () async {
    final pending = navigation.handle(
      command(
        WatchCommand.selectRemoteConversation,
        projectId: 'p-16',
        threadId: 't-16',
      ),
    );
    update(
      remote.copyWith(
        snapshotSequence: 11,
        selectedProjectId: 'p-16',
        currentConversationId: 't-16',
      ),
    );
    expect((await pending).ok, isTrue);

    final bound = command(
      WatchCommand.sendMessage,
      projectId: 'p-16',
      threadId: 't-16',
    );
    expect(navigation.validateSelectedDestination(bound).ok, isTrue);

    update(remote.copyWith(snapshotSequence: 12, currentConversationId: 't-0'));
    expect(
      navigation.validateSelectedDestination(bound).code,
      'destination_changed',
    );

    update(remote.copyWith(status: RemoteCodingConnectionStatus.disconnected));
    expect(
      navigation.validateSelectedDestination(bound).code,
      'remote_disconnected',
    );
    update(remote.copyWith(status: RemoteCodingConnectionStatus.connected));
    expect(
      navigation.validateSelectedDestination(bound).code,
      'remote_changed',
    );
  });

  test(
    'commands from an earlier connection cannot select or browse after reconnect',
    () async {
      final old = command(
        WatchCommand.selectRemoteConversation,
        projectId: 'p-16',
        threadId: 't-0',
      );
      update(
        remote.copyWith(status: RemoteCodingConnectionStatus.disconnected),
      );
      expect(navigation.snapshot().items, isEmpty);
      expect((await navigation.handle(old)).code, 'remote_disconnected');
      update(remote.copyWith(status: RemoteCodingConnectionStatus.connected));
      expect((await navigation.handle(old)).code, 'remote_changed');
      expect(selections, isEmpty);
    },
  );

  test('host changes retire pages and in-flight selections', () async {
    final old = command(WatchCommand.browseRemote, projectId: 'p-16');
    final pending = navigation.handle(
      command(
        WatchCommand.selectRemoteConversation,
        projectId: 'p-16',
        threadId: 't-0',
      ),
    );
    update(_remote(hostId: 'another-host'));
    expect((await pending).ok, isFalse);
    expect(navigation.snapshot().projectId, isNull);
    expect(navigation.snapshot().conversationId, isNull);
    expect((await navigation.handle(old)).code, 'remote_changed');
  });

  test('switching to local cancels an outstanding remote selection', () async {
    final pending = navigation.handle(
      command(
        WatchCommand.selectRemoteConversation,
        projectId: 'p-16',
        threadId: 't-0',
      ),
    );
    await navigation.handle(
      const WatchCommand(
        type: WatchCommand.selectSource,
        payload: {'source': 'local'},
      ),
    );
    expect((await pending).ok, isFalse);
    expect(navigation.source, 'local');
    expect(navigation.snapshot().conversationId, isNull);
  });

  test('socket enqueue without host confirmation times out visibly', () async {
    final result = await navigation.handle(
      command(
        WatchCommand.selectRemoteConversation,
        projectId: 'p-16',
        threadId: 't-0',
      ),
    );
    expect(result.code, 'selection_unconfirmed');
    expect(navigation.snapshot().selectionStatus, 'unconfirmed');
    expect(selections, ['t-0']);
  });

  test(
    'empty and removed projects are distinct, and shrinking pages remain reachable',
    () async {
      await navigation.handle(
        command(WatchCommand.browseRemote, projectId: 'p-0'),
      );
      expect(navigation.snapshot().items, isEmpty);
      expect(navigation.snapshot().selectionStatus, 'none');
      update(
        remote.copyWith(
          projects: remote.projects.where((p) => p.id != 'p-0').toList(),
        ),
      );
      expect(navigation.snapshot().selectionStatus, 'project_removed');
      await navigation.handle(command(WatchCommand.browseRemote, offset: 16));
      expect(navigation.snapshot().offset, 8);
      expect(navigation.snapshot().items, hasLength(8));
    },
  );

  test('removed thread cannot remain selected', () async {
    final pending = navigation.handle(
      command(
        WatchCommand.selectRemoteConversation,
        projectId: 'p-16',
        threadId: 't-0',
      ),
    );
    update(remote.copyWith(threads: []));
    expect((await pending).ok, isFalse);
    expect(navigation.snapshot().conversationId, isNull);
  });

  for (final codePoint in [0x754c, 0x1f600]) {
    test(
      'browser and full local transcript fit wide-script budget ($codePoint)',
      () {
        final wide = String.fromCharCodes(List.filled(500, codePoint));
        final browser = navigation.snapshot();
        final frame = WatchSnapshot(
          sequence: 1,
          generatedAt: DateTime.utc(2026, 9, 15),
          conversationTitle: wide,
          lastAssistantText: wide,
          messages: List.generate(
            8,
            (i) => WatchMessage(
              id: 'm-$i',
              role: WatchMessageRole.assistant,
              text: wide,
              timestamp: DateTime.utc(2026),
            ),
          ),
          conversations: List.generate(
            8,
            (i) => WatchConversation(id: 'c-$i', title: wide),
          ),
          goal: WatchGoal(
            objective: wide,
            status: 'awaitingConfirmation',
            completionSummary: wide,
            blockedReason: wide,
          ),
          remoteBrowser: WatchRemoteBrowser(
            hostId: browser.hostId,
            sessionId: browser.sessionId,
            hostName: wide,
            connectionStatus: 'connected',
            projectTitle: wide,
            conversationTitle: wide,
            items: List.generate(
              8,
              (i) => WatchRemoteItem(id: 'id-$i', title: wide),
            ),
            total: 17,
          ),
          approval: WatchApproval(
            id: 'a',
            kind: 'localCommand',
            title: wide,
            subtitle: wide,
            detail: wide,
            host: wide,
            canResolveOnWatch: true,
            source: WatchInteractionSource.remote,
          ),
          question: WatchQuestion(
            id: 'q',
            question: wide,
            host: wide,
            source: WatchInteractionSource.remote,
            options: List.generate(
              4,
              (i) => WatchQuestionOption(id: '$i', label: wide),
            ),
          ),
        );
        expect(
          utf8.encode(frame.encode()).length,
          lessThanOrEqualTo(watchSnapshotMaxEncodedBytes),
        );
        final decoded = WatchSnapshot.fromJson(frame.toJson());
        expect(decoded.transcriptSource, 'local');
        expect(decoded.remoteBrowser!.items, hasLength(8));
        expect(decoded.remoteBrowser!.total, 17);
        expect(decoded.remoteBrowser!.sessionId, browser.sessionId);
        expect(decoded.approval, isNotNull);
        expect(decoded.question, isNotNull);
        expect(decoded.goal, isNotNull);
      },
    );
  }
}

RemoteCodingClientState _remote({String hostId = 'host-1'}) =>
    RemoteCodingClientState(
      host: RemoteCodingHost(
        id: hostId,
        name: 'Desktop',
        host: '192.0.2.1',
        port: 8767,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        certificatePin: 'pin',
      ),
      status: RemoteCodingConnectionStatus.connected,
      supportsDestinationBoundCommands: true,
      snapshotSequence: 10,
      selectedProjectId: 'p-0',
      projects: List.generate(
        17,
        (i) => RemoteCodingProjectSummary(
          id: 'p-$i',
          name: 'Project $i',
          rootPath: '/private/project-$i',
        ),
      ),
      threads: List.generate(
        17,
        (i) => RemoteCodingThreadSummary(
          id: 't-$i',
          title: 'Thread $i',
          projectId: 'p-16',
          updatedAt: DateTime.utc(2026),
        ),
      ),
    );
