import 'dart:async';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/data/repositories/key_value_store.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/approval_notification_actions.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers Approve/Deny chosen from a notification — including on a paired
/// Apple Watch, which iOS hands the same actions to.
///
/// Two notifiers raise that notification now, and the approval id is what
/// decides which owns the request. Before this the action resolved only
/// against `ChatNotifier`, so a Remote Coding id resolved nothing at all, and
/// did so silently.
///
/// The real `ChatNotifier` is used rather than a stub. Its `resolve*` family
/// lives in an `extension` on the class, and extension methods are statically
/// dispatched — a subclass override compiles and is then never called, so a
/// stubbed chat notifier would report a passing test for a path it never ran.
/// A fresh notifier owns no approvals, which is exactly the condition these
/// tests need; the case where chat *does* own the id is covered where a real
/// pending approval can be produced, in the chat notifier's own tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingNotificationService notifications;
  late _RecordingRemoteCodingClient client;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    notifications = _RecordingNotificationService();
    client = _RecordingRemoteCodingClient();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        conversationRepositoryProvider.overrideWithValue(
          _InMemoryConversationRepository(),
        ),
        chatMemoryRepositoryProvider.overrideWithValue(
          ChatMemoryRepository(_MapKeyValueStore()),
        ),
        mcpToolServiceProvider.overrideWithValue(_StubMcpToolService()),
        notificationServiceProvider.overrideWithValue(notifications),
        remoteCodingClientProvider.overrideWith(() => client),
      ],
    );
    // A notifier has no state until its provider is read, and the test has to
    // set state on the client.
    container.read(chatNotifierProvider);
    container.read(remoteCodingClientProvider);
    container.read(approvalNotificationActionsProvider);
    addTearDown(container.dispose);
    addTearDown(notifications.dispose);
  });

  Future<void> act({
    required String approvalId,
    String actionId = NotificationService.approveActionId,
  }) async {
    notifications.emit(
      NotificationActionEvent(
        actionId: actionId,
        conversationId: 'conversation-1',
        approvalId: approvalId,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  RemoteCodingApproval approval({
    String id = 'remote-1',
    RemoteCodingApprovalKind kind = RemoteCodingApprovalKind.localCommand,
  }) => RemoteCodingApproval(
    id: id,
    kind: kind,
    title: 'dart analyze',
    subtitle: 'caverno',
    detail: '',
  );

  test('a remote approval resolves over the WebSocket', () async {
    client.setPendingApproval(approval());

    await act(approvalId: 'remote-1');

    expect(client.resolved, [(id: 'remote-1', approved: true)]);
  });

  test('Deny travels as a denial, not as a silent drop', () async {
    client.setPendingApproval(approval());

    await act(
      approvalId: 'remote-1',
      actionId: NotificationService.denyActionId,
    );

    expect(client.resolved, [(id: 'remote-1', approved: false)]);
  });

  test('every remote kind is answerable this way', () async {
    for (final kind in RemoteCodingApprovalKind.values) {
      client.setPendingApproval(approval(id: 'remote-${kind.name}', kind: kind));

      await act(approvalId: 'remote-${kind.name}');
    }

    expect(
      client.resolved.map((entry) => entry.id),
      RemoteCodingApprovalKind.values.map((kind) => 'remote-${kind.name}'),
    );
  });

  test('an id nothing owns resolves nothing', () async {
    // A stale notification must fail visibly rather than resolve whatever else
    // happens to be pending.
    client.setPendingApproval(approval());

    await act(approvalId: 'withdrawn');

    expect(client.resolved, isEmpty);
  });

  test('an action that is neither approve nor deny is ignored', () async {
    client.setPendingApproval(approval());

    await act(approvalId: 'remote-1', actionId: 'open');

    expect(client.resolved, isEmpty);
  });

  test('a remote id is not routed once the approval is gone', () async {
    client.setPendingApproval(approval());
    client.clearPendingApproval();

    await act(approvalId: 'remote-1');

    expect(client.resolved, isEmpty);
  });
}

final class _RecordingNotificationService extends NotificationService {
  final _controller = StreamController<NotificationActionEvent>.broadcast();

  @override
  Stream<NotificationActionEvent> get notificationActions => _controller.stream;

  void emit(NotificationActionEvent event) => _controller.add(event);

  @override
  void dispose() {
    unawaited(_controller.close());
  }
}

final class _RecordingRemoteCodingClient extends RemoteCodingClientNotifier {
  final resolved = <({String id, bool approved})>[];

  @override
  RemoteCodingClientState build() => const RemoteCodingClientState();

  void setPendingApproval(RemoteCodingApproval approval) {
    state = state.copyWith(pendingApproval: approval);
  }

  void clearPendingApproval() {
    state = state.copyWith(clearPendingApproval: true);
  }

  @override
  Future<void> resolveApproval({
    required String approvalId,
    required bool approved,
  }) async {
    resolved.add((id: approvalId, approved: approved));
  }
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
