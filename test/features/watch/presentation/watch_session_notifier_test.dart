import 'dart:async';

import 'package:caverno/core/services/watch_bridge_service.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/data/repositories/key_value_store.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/watch/domain/watch_command.dart';
import 'package:caverno/features/watch/domain/watch_snapshot.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/features/watch/presentation/watch_session_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the `WCSession` bridge so the command path can be driven
/// without an iOS host.
class _FakeWatchBridge implements WatchBridgeService {
  _FakeWatchBridge({this.available = true});

  bool available;
  int availabilityQueries = 0;
  final StreamController<WatchCommand> _commands =
      StreamController<WatchCommand>.broadcast();
  final List<WatchSnapshot> pushedSnapshots = [];
  final List<WatchCommandResult> results = [];
  final List<Map<String, Object>> streamChunks = [];

  @override
  Stream<WatchCommand> get commands => _commands.stream;

  @override
  Future<bool> isAvailable() async {
    availabilityQueries += 1;
    return available;
  }

  @override
  Future<void> pushSnapshot(WatchSnapshot snapshot) async {
    pushedSnapshots.add(snapshot);
  }

  @override
  Future<void> pushStreamChunk({
    required String turnId,
    required String text,
    required bool isFinal,
  }) async {
    streamChunks.add({'turnId': turnId, 'text': text, 'isFinal': isFinal});
  }

  @override
  Future<void> sendCommandResult(WatchCommandResult result) async {
    results.add(result);
  }

  @override
  void dispose() {
    _commands.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWatchBridge bridge;
  late SharedPreferences prefs;
  late ProviderContainer container;

  ProviderContainer buildContainer(_FakeWatchBridge watchBridge) =>
      ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Keeps the real ChatNotifier off Hive; the watch bridge only needs
          // its state, not its persistence.
          conversationRepositoryProvider.overrideWithValue(
            _InMemoryConversationRepository(),
          ),
          chatMemoryRepositoryProvider.overrideWithValue(
            ChatMemoryRepository(_MapKeyValueStore()),
          ),
          // Cuts the tool-catalogue provider graph, which otherwise pulls in
          // several Hive boxes the watch bridge has no interest in.
          mcpToolServiceProvider.overrideWithValue(_StubMcpToolService()),
          watchBridgeServiceProvider.overrideWithValue(watchBridge),
        ],
      );

  Future<WatchSessionNotifier> notifier() async {
    final instance = container.read(watchSessionProvider.notifier);
    // build() resolves availability asynchronously; snapshots are suppressed
    // until it lands, so every test has to let it settle first.
    await Future<void>.delayed(Duration.zero);
    return instance;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    bridge = _FakeWatchBridge();
    container = buildContainer(bridge);
    addTearDown(container.dispose);
  });

  test('availability is resolved from the bridge on build', () async {
    await notifier();

    expect(container.read(watchSessionProvider).isAvailable, isTrue);
  });

  test('an unavailable watch suppresses snapshot pushes', () async {
    container.dispose();
    bridge = _FakeWatchBridge(available: false);
    container = buildContainer(bridge);
    addTearDown(container.dispose);
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot, id: 'r-1'),
    );

    expect(bridge.pushedSnapshots, isEmpty);
    expect(bridge.results.single.ok, isTrue);
  });

  test('a watch that becomes available later still gets a frame', () async {
    // WCSession.activate() is asynchronous, so build() can legitimately see
    // "unavailable". Latching that answer left the watch on its connecting
    // screen forever after a phone restart.
    container.dispose();
    bridge = _FakeWatchBridge(available: false);
    container = buildContainer(bridge);
    addTearDown(container.dispose);
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );
    expect(bridge.pushedSnapshots, isEmpty);

    bridge.available = true;
    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );

    expect(bridge.pushedSnapshots, hasLength(1));
    expect(container.read(watchSessionProvider).isAvailable, isTrue);
  });

  test('an available watch is not re-queried on every push', () async {
    final instance = await notifier();
    final afterBuild = bridge.availabilityQueries;

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );
    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );

    expect(bridge.availabilityQueries, afterBuild);
  });

  test('requestSnapshot pushes a frame and acknowledges', () async {
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot, id: 'r-1'),
    );

    expect(bridge.pushedSnapshots, hasLength(1));
    expect(bridge.results.single.ok, isTrue);
    expect(bridge.results.single.id, 'r-1');
  });

  test('snapshot sequence increases so the watch can drop stale frames', () async {
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );
    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );

    final sequences = bridge.pushedSnapshots
        .map((snapshot) => snapshot.sequence)
        .toList();
    expect(sequences, [lessThan(sequences[1]), greaterThan(sequences[0])]);
    expect(
      container.read(watchSessionProvider).lastSequence,
      sequences.last,
    );
  });

  test('an unknown command is refused rather than ignored', () async {
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(type: 'somethingNewerThanThisBuild', id: 'x-1'),
    );

    final result = bridge.results.single;
    expect(result.ok, isFalse);
    expect(result.code, 'unsupported_command');
    expect(result.id, 'x-1');
  });

  test('an empty message is refused', () async {
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(
        type: WatchCommand.sendMessage,
        id: 's-1',
        payload: {'content': '   '},
      ),
    );

    expect(bridge.results.single.code, 'empty_message');
  });

  group('deferred command conversation binding', () {
    test('a message stamped for another thread is refused', () async {
      final instance = await notifier();
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation();

      await instance.handleCommandForTest(
        WatchCommand(
          type: WatchCommand.sendMessage,
          id: 's-1',
          payload: {
            'content': 'continue that',
            'conversationId': 'some-other-thread',
          },
        ),
      );

      final result = bridge.results.single;
      expect(result.ok, isFalse);
      expect(result.code, 'conversation_changed');
    });

    test('a message stamped for the open thread is accepted', () async {
      final instance = await notifier();
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation();
      final current = container
          .read(conversationsNotifierProvider)
          .currentConversation!
          .id;

      await instance.handleCommandForTest(
        WatchCommand(
          type: WatchCommand.sendMessage,
          id: 's-1',
          payload: {'content': 'hello', 'conversationId': current},
        ),
      );

      expect(bridge.results.single.ok, isTrue);
    });

    test('an unstamped message is still accepted', () async {
      // Older watch builds ship without the stamp; refusing them would break
      // the companion on a watch that has not synced the new app yet.
      final instance = await notifier();
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation();

      await instance.handleCommandForTest(
        const WatchCommand(
          type: WatchCommand.sendMessage,
          id: 's-1',
          payload: {'content': 'hello'},
        ),
      );

      expect(bridge.results.single.ok, isTrue);
    });
  });

  test('resolving an approval that is gone reports approval_not_found', () async {
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(
        type: WatchCommand.resolveApproval,
        id: 'a-1',
        payload: {'approvalId': 'stale', 'approved': true},
      ),
    );

    final result = bridge.results.single;
    expect(result.ok, isFalse);
    expect(result.code, 'approval_not_found');
    expect(container.read(watchSessionProvider).lastError, isNotEmpty);
  });

  test('resolving a question that is gone reports question_not_found', () async {
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(
        type: WatchCommand.resolveQuestion,
        id: 'q-1',
        payload: {'questionId': 'stale'},
      ),
    );

    expect(bridge.results.single.code, 'question_not_found');
  });

  test('cancelStreaming reaches the chat notifier and acknowledges', () async {
    final instance = await notifier();
    // Reading the notifier proves the provider is wired; cancelStreaming on an
    // idle thread is a no-op, so the assertion is that it does not throw and
    // that the watch still gets an answer.
    expect(container.read(chatNotifierProvider.notifier), isNotNull);

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.cancelStreaming, id: 'c-1'),
    );

    expect(bridge.results.single.ok, isTrue);
  });

  test('stream chunks carry only the newly appended text', () async {
    final instance = await notifier();

    await instance.pushStreamDeltaForTest('Reading the ');
    await instance.pushStreamDeltaForTest('Reading the failing test.');
    // An unchanged transcript must not re-push, or the watch reads it twice.
    await instance.pushStreamDeltaForTest('Reading the failing test.');

    // The contract is that concatenating the chunks reproduces the answer —
    // not where the boundaries fall. The projection trims each frame, so a
    // chunk edge can move by a space without the watch reading anything wrong.
    expect(bridge.streamChunks, hasLength(2));
    expect(
      bridge.streamChunks.map((chunk) => chunk['text']! as String).join(),
      'Reading the failing test.',
    );
  });

  test('internal markup never reaches the watch', () async {
    final instance = await notifier();

    // Session-memory extraction leaves a <tool_use> envelope in the raw
    // message content. The phone strips it at render time; projecting the raw
    // field put the JSON on the watch, where the speaker would read it aloud.
    await instance.pushStreamDeltaForTest(
      'Here is the answer.'
      '<tool_use>{"name":"memory-update","arguments":{"added":0}}</tool_use>',
    );

    expect(
      bridge.streamChunks.map((chunk) => chunk['text']! as String).join(),
      'Here is the answer.',
    );
  });

  test('reasoning blocks are stripped too', () async {
    final instance = await notifier();

    await instance.pushStreamDeltaForTest(
      '<think>weighing the options</think>The answer is four.',
    );

    expect(
      bridge.streamChunks.map((chunk) => chunk['text']! as String).join(),
      'The answer is four.',
    );
  });

  test('a replaced answer resends from the start', () async {
    final instance = await notifier();

    await instance.pushStreamDeltaForTest('Original answer.');
    // A claim guard can rewrite the visible message rather than extend it.
    await instance.pushStreamDeltaForTest('Corrected answer.');

    expect(
      bridge.streamChunks.map((chunk) => chunk['text']),
      ['Original answer.', 'Corrected answer.'],
    );
  });

  test('an untitled conversation does not leak its sentinel title', () async {
    final instance = await notifier();
    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation();

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );

    final snapshot = bridge.pushedSnapshots.last;
    expect(snapshot.conversationId, isNotNull);
    expect(
      snapshot.conversationTitle,
      isEmpty,
      reason:
          'defaultConversationTitle is a marker, not a label; passing it '
          'through put a literal __new_conversation__ on the watch.',
    );
  });

  test('an idle snapshot reports no pending interaction', () async {
    final instance = await notifier();

    await instance.handleCommandForTest(
      const WatchCommand(type: WatchCommand.requestSnapshot),
    );

    final snapshot = bridge.pushedSnapshots.single;
    expect(snapshot.status, WatchTurnStatus.idle);
    expect(snapshot.approval, isNull);
    expect(snapshot.question, isNull);
    expect(snapshot.needsAttention, isFalse);
    expect(snapshot.elapsedSeconds, 0);
  });
}

class _InMemoryConversationRepository implements ConversationRepositoryApi {
  final Map<String, Conversation> _conversations = {};

  @override
  List<Conversation> getAll() => _conversations.values.toList(growable: false);

  @override
  Conversation? getById(String id) => _conversations[id];

  @override
  Future<Conversation?> refresh(String id) async => _conversations[id];

  @override
  Future<void> save(Conversation conversation) async {
    _conversations[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _conversations.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _conversations.clear();
  }

  @override
  Future<List<Conversation>> search(String query) async => getAll();
}

class _MapKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  bool get isReady => true;

  @override
  String? get(String key) => _values[key];

  @override
  Future<void> refresh(Iterable<String> keys) async {}

  @override
  Future<void> put(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _StubMcpToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() =>
      const <Map<String, dynamic>>[];
}
