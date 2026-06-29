import 'dart:async';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_protocol.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_server_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();
}

class _DashboardConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() {
    final conversation = Conversation(
      id: 'chat-1',
      title: 'Desktop chat',
      messages: [
        Message(
          id: 'user-1',
          content: 'Hello',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 1, 9),
        ),
        Message(
          id: 'assistant-1',
          content: 'Hi',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 1, 9, 1),
          responseMetrics: const MessageResponseMetrics(totalTokens: 2048),
        ),
      ],
      createdAt: DateTime(2026, 6, 1, 9),
      updatedAt: DateTime(2026, 6, 1, 9, 1),
    );
    return ConversationsState(
      conversations: [conversation],
      currentConversationId: conversation.id,
      activeWorkspaceMode: WorkspaceMode.chat,
      activeProjectId: null,
    );
  }
}

class _TestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for remote coding server test condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('canceling a pairing payload invalidates the ticket', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final port = await _unusedPort();
    await RemoteCodingRepository(
      prefs,
    ).saveServerSettings(RemoteCodingServerSettings(enabled: true, port: port));
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatNotifierProvider.overrideWith(_TestChatNotifier.new),
      ],
    );

    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    final messages = <RemoteCodingProtocolMessage>[];
    try {
      container.read(remoteCodingServerProvider);
      await _waitUntil(
        () => container.read(remoteCodingServerProvider).isRunning,
      );
      final payload = await container
          .read(remoteCodingServerProvider.notifier)
          .createPairingPayload();
      expect(payload, isNotNull);

      container
          .read(remoteCodingServerProvider.notifier)
          .cancelPairingPayload(payload!.ticketId);
      expect(container.read(remoteCodingServerProvider).pairingPayload, isNull);

      socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      subscription = socket.listen((raw) {
        if (raw is String) {
          messages.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      socket.add(
        RemoteCodingProtocol.encode(
          type: 'auth',
          id: 'auth-canceled',
          payload: {
            'ticketId': payload.ticketId,
            'secret': payload.secret,
            'deviceName': 'Phone',
          },
        ),
      );

      await _waitUntil(
        () => messages.any(
          (message) =>
              message.id == 'auth-canceled' &&
              message.type == 'error' &&
              message.payload['code'] == 'pairing_failed',
        ),
      );
    } finally {
      await subscription?.cancel();
      await socket?.close();
      container.dispose();
    }
  });

  test('authenticated snapshots include desktop dashboard stats', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final port = await _unusedPort();
    const rawToken = 'mobile-token';
    final device = RemoteCodingPairedDevice(
      id: 'device-1',
      name: 'Phone',
      tokenHash: RemoteCodingSecurity.hashToken(rawToken),
      createdAt: DateTime(2026, 5, 26, 12),
      lastSeenAt: DateTime(2026, 5, 26, 12),
    );
    await RemoteCodingRepository(prefs).saveServerSettings(
      RemoteCodingServerSettings(
        enabled: true,
        port: port,
        pairedDevices: [device],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _DashboardConversationsNotifier.new,
        ),
        chatNotifierProvider.overrideWith(_TestChatNotifier.new),
      ],
    );

    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    final messages = <RemoteCodingProtocolMessage>[];
    try {
      container.read(remoteCodingServerProvider);
      await _waitUntil(
        () => container.read(remoteCodingServerProvider).isRunning,
      );

      socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      subscription = socket.listen((raw) {
        if (raw is String) {
          messages.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      socket.add(
        RemoteCodingProtocol.encode(
          type: 'auth',
          id: 'auth-dashboard',
          payload: const {'token': rawToken},
        ),
      );
      await _waitUntil(
        () => messages.any(
          (message) =>
              message.id == 'auth-dashboard' && message.type == 'snapshot',
        ),
      );

      final snapshot = messages.firstWhere(
        (message) =>
            message.id == 'auth-dashboard' && message.type == 'snapshot',
      );
      final statsByRange =
          snapshot.payload['dashboardStatsByRange'] as Map<String, dynamic>;
      final allStats = statsByRange['all'] as Map<String, dynamic>;

      expect(allStats['sessionCount'], 1);
      expect(allStats['messageCount'], 2);
      expect(allStats['totalTokens'], 2048);
    } finally {
      await subscription?.cancel();
      await socket?.close();
      container.dispose();
    }
  });

  test('revoking a paired device disconnects active sockets', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final port = await _unusedPort();
    const rawToken = 'mobile-token';
    final device = RemoteCodingPairedDevice(
      id: 'device-1',
      name: 'Phone',
      tokenHash: RemoteCodingSecurity.hashToken(rawToken),
      createdAt: DateTime(2026, 5, 26, 12),
      lastSeenAt: DateTime(2026, 5, 26, 12),
    );
    await RemoteCodingRepository(prefs).saveServerSettings(
      RemoteCodingServerSettings(
        enabled: true,
        port: port,
        pairedDevices: [device],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatNotifierProvider.overrideWith(_TestChatNotifier.new),
      ],
    );

    WebSocket? socket;
    StreamSubscription<dynamic>? subscription;
    final messages = <RemoteCodingProtocolMessage>[];
    final closed = Completer<void>();
    try {
      container.read(remoteCodingServerProvider);
      await _waitUntil(
        () => container.read(remoteCodingServerProvider).isRunning,
      );

      socket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      subscription = socket.listen(
        (raw) {
          if (raw is String) {
            messages.add(RemoteCodingProtocolMessage.decode(raw));
          }
        },
        onDone: () {
          if (!closed.isCompleted) {
            closed.complete();
          }
        },
      );
      socket.add(
        RemoteCodingProtocol.encode(
          type: 'auth',
          id: 'auth-1',
          payload: const {'token': rawToken},
        ),
      );
      await _waitUntil(
        () => messages.any(
          (message) => message.id == 'auth-1' && message.type == 'snapshot',
        ),
      );
      expect(
        container.read(remoteCodingServerProvider).activeConnectionCount,
        1,
      );

      await container
          .read(remoteCodingServerProvider.notifier)
          .revokeDevice(device.id);

      await _waitUntil(
        () => messages.any((message) => message.type == 'disconnected'),
      );
      await closed.future.timeout(const Duration(seconds: 3));
      await _waitUntil(
        () =>
            container.read(remoteCodingServerProvider).activeConnectionCount ==
            0,
      );

      final rejectedSocket = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      final rejectedMessages = <RemoteCodingProtocolMessage>[];
      final rejectedSubscription = rejectedSocket.listen((raw) {
        if (raw is String) {
          rejectedMessages.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      try {
        rejectedSocket.add(
          RemoteCodingProtocol.encode(
            type: 'auth',
            id: 'auth-2',
            payload: const {'token': rawToken},
          ),
        );
        await _waitUntil(
          () => rejectedMessages.any(
            (message) =>
                message.id == 'auth-2' &&
                message.type == 'error' &&
                message.payload['code'] == 'unauthorized',
          ),
        );
      } finally {
        await rejectedSubscription.cancel();
        await rejectedSocket.close();
      }
    } finally {
      await subscription?.cancel();
      await socket?.close();
      container.dispose();
    }
  });
}
