import 'dart:async';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_client.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_pairing.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_providers.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_protocol.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_secure_store.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_websocket_connector.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_resource_policy.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_session_policy.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_server_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
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

final class _MemorySecureStore implements RemoteCodingSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

final class _ProvisioningRelayClient
    implements RemoteCodingNotificationRelayClient {
  int redemptionCount = 0;
  int activationCount = 0;
  RemoteCodingRelayDelegationRedemptionRequest? redemptionRequest;

  @override
  Future<RemoteCodingRelayDelegationRedemptionResponse> redeemDelegation({
    required String delegationId,
    required RemoteCodingRelayDelegationRedemptionRequest request,
  }) async {
    redemptionCount += 1;
    redemptionRequest = request;
    return RemoteCodingRelayDelegationRedemptionResponse(
      delegationId: delegationId,
      deliveryHandle: 'delivery_handle_1',
      deliveryKeyId: 'delivery-key-1',
      deliverySecret: 'desktop-delivery-secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );
  }

  @override
  Future<void> activateDelegation({
    required String deliveryHandle,
    required String delegationId,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDelegationActivationRequest request,
  }) async {
    activationCount += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<WebSocket> _connectPinned(ProviderContainer container, int port) {
  final pin = container.read(remoteCodingServerProvider).certificatePin;
  expect(pin, isNotNull);
  return connectPinnedRemoteCodingWebSocket(
    url: 'wss://127.0.0.1:$port/ws',
    certificatePin: pin!,
  );
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for remote coding server test condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<WebSocket> _waitForPinnedConnection(
  ProviderContainer container,
  int port,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (true) {
    try {
      return await _connectPinned(container, port);
    } on WebSocketException {
      if (DateTime.now().isAfter(deadline)) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

Future<({ProviderContainer container, int port})> _startResourceLimitedServer({
  required RemoteCodingResourcePolicy policy,
  List<RemoteCodingPairedDevice> pairedDevices = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final port = await _unusedPort();
  await RemoteCodingRepository(prefs).saveServerSettings(
    RemoteCodingServerSettings(
      enabled: true,
      port: port,
      pairedDevices: pairedDevices,
    ),
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      remoteCodingRepositoryProvider.overrideWithValue(
        RemoteCodingRepository(prefs, secureStore: _MemorySecureStore()),
      ),
      remoteCodingResourcePolicyProvider.overrideWithValue(policy),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifier.new,
      ),
      conversationsNotifierProvider.overrideWith(
        _TestConversationsNotifier.new,
      ),
      chatNotifierProvider.overrideWith(_TestChatNotifier.new),
    ],
  );
  container.read(remoteCodingServerProvider);
  await _waitUntil(() => container.read(remoteCodingServerProvider).isRunning);
  return (container: container, port: port);
}

String _certificatePin(ProviderContainer container) {
  final pin = container.read(remoteCodingServerProvider).certificatePin;
  expect(pin, isNotNull);
  expect(pin, isNotEmpty);
  return pin!;
}

Future<RemoteCodingSessionChallenge> _waitForChallenge(
  List<RemoteCodingProtocolMessage> messages,
) async {
  await _waitUntil(
    () => messages.any((message) => message.type == 'authChallenge'),
  );
  return RemoteCodingSessionChallenge.fromPayload(
    messages.firstWhere((message) => message.type == 'authChallenge').payload,
  );
}

void _sendChallengedAuth(
  WebSocket socket, {
  required String id,
  required RemoteCodingSessionChallenge challenge,
  required String certificatePin,
  required String credential,
  String? token,
  String? ticketId,
  String? secret,
  String? deviceName,
}) {
  socket.add(
    RemoteCodingProtocol.encode(
      type: 'auth',
      id: id,
      payload: {
        'challengeId': challenge.challengeId,
        'proof': RemoteCodingSessionPolicy.proof(
          credential: credential,
          challengeId: challenge.challengeId,
          nonce: challenge.nonce,
          certificatePin: certificatePin,
        ),
        'token': ?token,
        'ticketId': ?ticketId,
        'secret': ?secret,
        'deviceName': ?deviceName,
      },
    ),
  );
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
        remoteCodingRepositoryProvider.overrideWithValue(
          RemoteCodingRepository(prefs, secureStore: _MemorySecureStore()),
        ),
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

      socket = await _connectPinned(container, port);
      subscription = socket.listen((raw) {
        if (raw is String) {
          messages.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      final challenge = await _waitForChallenge(messages);
      _sendChallengedAuth(
        socket,
        id: 'auth-canceled',
        challenge: challenge,
        certificatePin: _certificatePin(container),
        credential: payload.secret,
        ticketId: payload.ticketId,
        secret: payload.secret,
        deviceName: 'Phone',
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
        remoteCodingRepositoryProvider.overrideWithValue(
          RemoteCodingRepository(prefs, secureStore: _MemorySecureStore()),
        ),
        remoteCodingResourcePolicyProvider.overrideWithValue(
          const RemoteCodingResourcePolicy(
            authenticationDeadline: Duration(milliseconds: 100),
          ),
        ),
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

      socket = await _connectPinned(container, port);
      subscription = socket.listen((raw) {
        if (raw is String) {
          messages.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      final challenge = await _waitForChallenge(messages);
      _sendChallengedAuth(
        socket,
        id: 'auth-dashboard',
        challenge: challenge,
        certificatePin: _certificatePin(container),
        credential: rawToken,
        token: rawToken,
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
      final auth = snapshot.payload['auth'] as Map<String, dynamic>;
      expect(auth['sessionId'], isNotEmpty);
      expect(auth['sessionId'], isNot(rawToken));
      expect(auth.containsKey('deviceToken'), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      socket.add(
        RemoteCodingProtocol.encode(
          type: 'requestSnapshot',
          id: 'after-auth-deadline',
          payload: const {},
        ),
      );
      await _waitUntil(
        () => messages.any(
          (message) =>
              message.id == 'after-auth-deadline' && message.type == 'snapshot',
        ),
      );
    } finally {
      await subscription?.cancel();
      await socket?.close();
      container.dispose();
    }
  });

  test(
    'authenticated clients receive only remote-origin terminal payloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final port = await _unusedPort();
      const rawToken = 'mobile-token';
      final device = RemoteCodingPairedDevice(
        id: 'device-1',
        name: 'Phone',
        tokenHash: RemoteCodingSecurity.hashToken(rawToken),
        createdAt: DateTime(2026, 8, 10, 14),
        lastSeenAt: DateTime(2026, 8, 10, 14),
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
          remoteCodingRepositoryProvider.overrideWithValue(
            RemoteCodingRepository(prefs, secureStore: _MemorySecureStore()),
          ),
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

        socket = await _connectPinned(container, port);
        subscription = socket.listen((raw) {
          if (raw is String) {
            messages.add(RemoteCodingProtocolMessage.decode(raw));
          }
        });
        final challenge = await _waitForChallenge(messages);
        _sendChallengedAuth(
          socket,
          id: 'auth-terminal',
          challenge: challenge,
          certificatePin: _certificatePin(container),
          credential: rawToken,
          token: rawToken,
        );
        await _waitUntil(
          () => messages.any(
            (message) =>
                message.id == 'auth-terminal' && message.type == 'snapshot',
          ),
        );

        final notifier = container.read(remoteCodingServerProvider.notifier);
        notifier.handleRuntimeEventForTest(
          CavernoRuntimeRunCompleted(
            sequence: 1,
            timestamp: DateTime.utc(2026, 8, 10, 14, 30),
            turnId: 'gen-15',
            conversationId: 'conversation-15',
            interactionOrigin: CavernoRuntimeInteractionOrigin.remoteCoding,
            content: 'Private model result',
          ),
        );
        await _waitUntil(
          () => messages.any((message) => message.type == 'runTerminal'),
        );

        final terminal = messages.singleWhere(
          (message) => message.type == 'runTerminal',
        );
        final payload = RemoteCodingNotificationPayload.fromFcmData(
          terminal.payload,
        );
        expect(payload.eventId, isNotEmpty);
        expect(payload.turnId, 'gen-15');
        expect(payload.conversationId, 'conversation-15');
        expect(payload.outcome, RemoteCodingNotificationOutcome.completed);
        expect(
          terminal.payload.values,
          isNot(contains('Private model result')),
        );

        notifier.handleRuntimeEventForTest(
          CavernoRuntimeRunCompleted(
            sequence: 2,
            timestamp: DateTime.utc(2026, 8, 10, 14, 31),
            turnId: 'gen-local',
            conversationId: 'conversation-local',
            content: 'Local model result',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          messages.where((message) => message.type == 'runTerminal'),
          hasLength(1),
        );
      } finally {
        await subscription?.cancel();
        await socket?.close();
        container.dispose();
      }
    },
  );

  test('authenticated device completes relay redemption over HTTPS', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final port = await _unusedPort();
    const rawToken = 'mobile-token';
    final secureStore = _MemorySecureStore();
    final repository = RemoteCodingRepository(prefs, secureStore: secureStore);
    final relayClient = _ProvisioningRelayClient();
    final device = RemoteCodingPairedDevice(
      id: 'device-1',
      name: 'Phone',
      tokenHash: RemoteCodingSecurity.hashToken(rawToken),
      createdAt: DateTime.now(),
      lastSeenAt: DateTime.now(),
    );
    await repository.saveServerSettings(
      RemoteCodingServerSettings(
        enabled: true,
        port: port,
        pairedDevices: [device],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        remoteCodingRepositoryProvider.overrideWithValue(repository),
        remoteCodingNotificationRelayClientProvider.overrideWithValue(
          relayClient,
        ),
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
      final qr = await container
          .read(remoteCodingServerProvider.notifier)
          .createNotificationRelayPairingPayload(device.id);
      expect(qr, isNotNull);

      socket = await _connectPinned(container, port);
      subscription = socket.listen((raw) {
        if (raw is String) {
          messages.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      final challenge = await _waitForChallenge(messages);
      _sendChallengedAuth(
        socket,
        id: 'auth-relay',
        challenge: challenge,
        certificatePin: _certificatePin(container),
        credential: rawToken,
        token: rawToken,
      );
      await _waitUntil(
        () => messages.any((message) => message.id == 'auth-relay'),
      );
      socket.add(
        RemoteCodingProtocol.encode(
          type: 'relayDelegationReady',
          id: 'relay-ready',
          payload: RemoteCodingRelayDelegationReadyMessage(
            challengeId: qr!.challengeId,
            delegationId: 'delegation-1',
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
          ).toPayload(),
        ),
      );
      await _waitUntil(
        () => messages.any(
          (message) =>
              message.id == 'relay-ready' && message.type == 'snapshot',
        ),
      );

      expect(relayClient.redemptionCount, 1);
      expect(relayClient.activationCount, 1);
      expect(
        relayClient.redemptionRequest?.challengeSecret,
        qr.challengeSecret,
      );
      final configured = repository.loadServerSettings().pairedDevices.single;
      expect(configured.relayDelegationId, 'delegation-1');
      expect(
        configured.relayCredentialState,
        RemoteCodingRelayCredentialState.active,
      );
      expect(
        await repository.loadDesktopRelayDeliverySecret(device.id),
        'desktop-delivery-secret',
      );
    } finally {
      await subscription?.cancel();
      await socket?.close();
      container.dispose();
    }
  });

  test(
    'revoking disconnects sockets and retains relay cleanup for retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final port = await _unusedPort();
      const rawToken = 'mobile-token';
      final secureStore = _MemorySecureStore();
      final repository = RemoteCodingRepository(
        prefs,
        secureStore: secureStore,
      );
      final device = RemoteCodingPairedDevice(
        id: 'device-1',
        name: 'Phone',
        tokenHash: RemoteCodingSecurity.hashToken(rawToken),
        createdAt: DateTime(2026, 5, 26, 12),
        lastSeenAt: DateTime(2026, 5, 26, 12),
        relayDeliveryHandle: 'delivery_handle_1',
        relayDeliveryKeyId: 'delivery-key-1',
        relayCredentialExpiresAt: DateTime(2026, 6, 26, 12),
      );
      await repository.saveDesktopRelayDeliverySecret(
        deviceId: device.id,
        deliverySecret: 'relay-delivery-secret',
      );
      await repository.saveServerSettings(
        RemoteCodingServerSettings(
          enabled: true,
          port: port,
          pairedDevices: [device],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteCodingRepositoryProvider.overrideWithValue(repository),
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

        socket = await _connectPinned(container, port);
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
        final challenge = await _waitForChallenge(messages);
        _sendChallengedAuth(
          socket,
          id: 'auth-1',
          challenge: challenge,
          certificatePin: _certificatePin(container),
          credential: rawToken,
          token: rawToken,
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

        expect(
          await repository.loadDesktopRelayDeliverySecret(device.id),
          'relay-delivery-secret',
        );
        final pendingDevice = repository
            .loadServerSettings()
            .pairedDevices
            .single;
        expect(pendingDevice.tokenHash, isEmpty);
        expect(
          pendingDevice.relayCredentialState,
          RemoteCodingRelayCredentialState.pendingRevocation,
        );

        await _waitUntil(
          () => messages.any((message) => message.type == 'disconnected'),
        );
        await closed.future.timeout(const Duration(seconds: 3));
        await _waitUntil(
          () =>
              container
                  .read(remoteCodingServerProvider)
                  .activeConnectionCount ==
              0,
        );

        final rejectedSocket = await _connectPinned(container, port);
        final rejectedMessages = <RemoteCodingProtocolMessage>[];
        final rejectedSubscription = rejectedSocket.listen((raw) {
          if (raw is String) {
            rejectedMessages.add(RemoteCodingProtocolMessage.decode(raw));
          }
        });
        try {
          final rejectedChallenge = await _waitForChallenge(rejectedMessages);
          _sendChallengedAuth(
            rejectedSocket,
            id: 'auth-2',
            challenge: rejectedChallenge,
            certificatePin: _certificatePin(container),
            credential: rawToken,
            token: rawToken,
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
    },
  );

  test('session auth requires a live challenge bound to that socket', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final port = await _unusedPort();
    const rawToken = 'mobile-token';
    final device = RemoteCodingPairedDevice(
      id: 'device-1',
      name: 'Phone',
      tokenHash: RemoteCodingSecurity.hashToken(rawToken),
      createdAt: DateTime(2026, 8, 21, 10),
      lastSeenAt: DateTime(2026, 8, 21, 10),
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
        remoteCodingRepositoryProvider.overrideWithValue(
          RemoteCodingRepository(prefs, secureStore: _MemorySecureStore()),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatNotifierProvider.overrideWith(_TestChatNotifier.new),
      ],
    );

    WebSocket? socketA;
    WebSocket? socketB;
    StreamSubscription<dynamic>? subscriptionA;
    StreamSubscription<dynamic>? subscriptionB;
    final messagesA = <RemoteCodingProtocolMessage>[];
    final messagesB = <RemoteCodingProtocolMessage>[];
    try {
      container.read(remoteCodingServerProvider);
      await _waitUntil(
        () => container.read(remoteCodingServerProvider).isRunning,
      );
      final pin = _certificatePin(container);

      socketA = await _connectPinned(container, port);
      subscriptionA = socketA.listen((raw) {
        if (raw is String) {
          messagesA.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      final challengeA = await _waitForChallenge(messagesA);

      socketB = await _connectPinned(container, port);
      subscriptionB = socketB.listen((raw) {
        if (raw is String) {
          messagesB.add(RemoteCodingProtocolMessage.decode(raw));
        }
      });
      await _waitForChallenge(messagesB);

      socketA.add(
        RemoteCodingProtocol.encode(
          type: 'auth',
          id: 'auth-token-only',
          payload: const {'token': rawToken},
        ),
      );
      await _waitUntil(
        () => messagesA.any(
          (message) =>
              message.id == 'auth-token-only' &&
              message.type == 'error' &&
              message.payload['code'] ==
                  RemoteCodingSessionPolicy.challengeRequiredCode,
        ),
      );

      _sendChallengedAuth(
        socketB,
        id: 'auth-foreign',
        challenge: challengeA,
        certificatePin: pin,
        credential: rawToken,
        token: rawToken,
      );
      await _waitUntil(
        () => messagesB.any(
          (message) =>
              message.id == 'auth-foreign' &&
              message.type == 'error' &&
              message.payload['code'] ==
                  RemoteCodingSessionPolicy.challengeRejectedCode,
        ),
      );

      _sendChallengedAuth(
        socketA,
        id: 'auth-owner',
        challenge: challengeA,
        certificatePin: pin,
        credential: rawToken,
        token: rawToken,
      );
      await _waitUntil(
        () => messagesA.any(
          (message) => message.id == 'auth-owner' && message.type == 'snapshot',
        ),
      );
      final snapshot = messagesA.firstWhere(
        (message) => message.id == 'auth-owner' && message.type == 'snapshot',
      );
      final auth = snapshot.payload['auth'] as Map<String, dynamic>;
      expect(auth['sessionId'], isNotEmpty);
      expect(auth['sessionId'], isNot(rawToken));
      expect(auth.containsKey('deviceToken'), isFalse);

      _sendChallengedAuth(
        socketB,
        id: 'auth-replay',
        challenge: challengeA,
        certificatePin: pin,
        credential: rawToken,
        token: rawToken,
      );
      await _waitUntil(
        () => messagesB.any(
          (message) =>
              message.id == 'auth-replay' &&
              message.type == 'error' &&
              message.payload['code'] ==
                  RemoteCodingSessionPolicy.challengeRejectedCode,
        ),
      );
    } finally {
      await subscriptionA?.cancel();
      await subscriptionB?.cancel();
      await socketA?.close();
      await socketB?.close();
      container.dispose();
    }
  });

  test('rejects excess sockets from the same peer before upgrade', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final port = await _unusedPort();
    await RemoteCodingRepository(
      prefs,
    ).saveServerSettings(RemoteCodingServerSettings(enabled: true, port: port));
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        remoteCodingRepositoryProvider.overrideWithValue(
          RemoteCodingRepository(prefs, secureStore: _MemorySecureStore()),
        ),
        remoteCodingResourcePolicyProvider.overrideWithValue(
          const RemoteCodingResourcePolicy(
            maxConnections: 2,
            maxConnectionsPerAddress: 1,
            authenticationDeadline: Duration(seconds: 5),
          ),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatNotifierProvider.overrideWith(_TestChatNotifier.new),
      ],
    );

    WebSocket? firstSocket;
    try {
      container.read(remoteCodingServerProvider);
      await _waitUntil(
        () => container.read(remoteCodingServerProvider).isRunning,
      );
      firstSocket = await _connectPinned(container, port);

      await expectLater(
        _connectPinned(container, port),
        throwsA(
          isA<WebSocketException>().having(
            (error) => error.toString(),
            'description',
            contains('${HttpStatus.tooManyRequests}'),
          ),
        ),
      );
    } finally {
      await firstSocket?.close();
      container.dispose();
    }
  });

  test(
    'closes unauthenticated sockets at the deadline and releases capacity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final port = await _unusedPort();
      await RemoteCodingRepository(prefs).saveServerSettings(
        RemoteCodingServerSettings(enabled: true, port: port),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteCodingRepositoryProvider.overrideWithValue(
            RemoteCodingRepository(prefs, secureStore: _MemorySecureStore()),
          ),
          remoteCodingResourcePolicyProvider.overrideWithValue(
            const RemoteCodingResourcePolicy(
              maxConnections: 1,
              maxConnectionsPerAddress: 1,
              authenticationDeadline: Duration(milliseconds: 100),
            ),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatNotifierProvider.overrideWith(_TestChatNotifier.new),
        ],
      );

      WebSocket? expiredSocket;
      WebSocket? replacementSocket;
      StreamSubscription<dynamic>? expiredSubscription;
      try {
        container.read(remoteCodingServerProvider);
        await _waitUntil(
          () => container.read(remoteCodingServerProvider).isRunning,
        );
        expiredSocket = await _connectPinned(container, port);
        final closed = Completer<void>();
        expiredSubscription = expiredSocket.listen(
          (_) {},
          onDone: closed.complete,
        );

        await closed.future.timeout(const Duration(seconds: 3));
        replacementSocket = await _waitForPinnedConnection(container, port);
      } finally {
        await expiredSubscription?.cancel();
        await expiredSocket?.close();
        await replacementSocket?.close();
        container.dispose();
      }
    },
  );

  for (final frameCase in <({String name, Object value})>[
    (name: 'text', value: 'x' * 65),
    (name: 'binary', value: List<int>.filled(65, 0)),
  ]) {
    test(
      'closes oversized ${frameCase.name} frames and releases capacity',
      () async {
        final server = await _startResourceLimitedServer(
          policy: const RemoteCodingResourcePolicy(
            maxConnections: 1,
            maxConnectionsPerAddress: 1,
            authenticationDeadline: Duration(seconds: 5),
            maxInboundFrameBytes: 64,
          ),
        );
        WebSocket? socket;
        WebSocket? replacementSocket;
        StreamSubscription<dynamic>? subscription;
        final messages = <RemoteCodingProtocolMessage>[];
        final closed = Completer<void>();
        try {
          socket = await _connectPinned(server.container, server.port);
          subscription = socket.listen((raw) {
            if (raw is String) {
              messages.add(RemoteCodingProtocolMessage.decode(raw));
            }
          }, onDone: closed.complete);

          socket.add(frameCase.value);
          await _waitUntil(
            () => messages.any(
              (message) =>
                  message.type == 'error' &&
                  message.payload['code'] ==
                      RemoteCodingResourcePolicy.frameTooLargeCode,
            ),
          );
          await closed.future.timeout(const Duration(seconds: 3));
          expect(socket.closeCode, WebSocketStatus.messageTooBig);

          replacementSocket = await _waitForPinnedConnection(
            server.container,
            server.port,
          );
        } finally {
          await subscription?.cancel();
          await socket?.close();
          await replacementSocket?.close();
          server.container.dispose();
        }
      },
    );
  }

  test(
    'closes an unauthenticated client that exceeds its message rate',
    () async {
      final server = await _startResourceLimitedServer(
        policy: const RemoteCodingResourcePolicy(
          authenticationDeadline: Duration(seconds: 5),
          maxUnauthenticatedMessagesPerWindow: 1,
        ),
      );
      WebSocket? socket;
      StreamSubscription<dynamic>? subscription;
      final messages = <RemoteCodingProtocolMessage>[];
      final closed = Completer<void>();
      try {
        socket = await _connectPinned(server.container, server.port);
        subscription = socket.listen((raw) {
          if (raw is String) {
            messages.add(RemoteCodingProtocolMessage.decode(raw));
          }
        }, onDone: closed.complete);
        await _waitForChallenge(messages);
        final request = RemoteCodingProtocol.encode(
          type: 'requestSnapshot',
          id: 'unauthenticated-rate',
          payload: const {},
        );

        socket
          ..add(request)
          ..add(request);

        await _waitUntil(
          () => messages.any(
            (message) =>
                message.type == 'error' &&
                message.payload['code'] ==
                    RemoteCodingResourcePolicy.messageRateExceededCode,
          ),
        );
        await closed.future.timeout(const Duration(seconds: 3));
        expect(socket.closeCode, WebSocketStatus.policyViolation);
      } finally {
        await subscription?.cancel();
        await socket?.close();
        server.container.dispose();
      }
    },
  );

  test(
    'gives an authenticated client a separate bounded message budget',
    () async {
      const rawToken = 'rate-limited-mobile-token';
      final device = RemoteCodingPairedDevice(
        id: 'rate-limited-device',
        name: 'Phone',
        tokenHash: RemoteCodingSecurity.hashToken(rawToken),
        createdAt: DateTime(2026, 8, 22, 12),
        lastSeenAt: DateTime(2026, 8, 22, 12),
      );
      final server = await _startResourceLimitedServer(
        policy: const RemoteCodingResourcePolicy(
          authenticationDeadline: Duration(seconds: 5),
          maxUnauthenticatedMessagesPerWindow: 1,
          maxAuthenticatedMessagesPerWindow: 1,
        ),
        pairedDevices: [device],
      );
      WebSocket? socket;
      StreamSubscription<dynamic>? subscription;
      final messages = <RemoteCodingProtocolMessage>[];
      final closed = Completer<void>();
      try {
        socket = await _connectPinned(server.container, server.port);
        subscription = socket.listen((raw) {
          if (raw is String) {
            messages.add(RemoteCodingProtocolMessage.decode(raw));
          }
        }, onDone: closed.complete);
        final challenge = await _waitForChallenge(messages);
        _sendChallengedAuth(
          socket,
          id: 'rate-auth',
          challenge: challenge,
          certificatePin: _certificatePin(server.container),
          credential: rawToken,
          token: rawToken,
        );
        await _waitUntil(
          () => messages.any(
            (message) =>
                message.id == 'rate-auth' && message.type == 'snapshot',
          ),
        );

        socket.add(
          RemoteCodingProtocol.encode(
            type: 'requestSnapshot',
            id: 'within-authenticated-rate',
            payload: const {},
          ),
        );
        await _waitUntil(
          () => messages.any(
            (message) =>
                message.id == 'within-authenticated-rate' &&
                message.type == 'snapshot',
          ),
        );
        socket.add(
          RemoteCodingProtocol.encode(
            type: 'requestSnapshot',
            id: 'over-authenticated-rate',
            payload: const {},
          ),
        );

        await _waitUntil(
          () => messages.any(
            (message) =>
                message.type == 'error' &&
                message.payload['code'] ==
                    RemoteCodingResourcePolicy.messageRateExceededCode,
          ),
        );
        await closed.future.timeout(const Duration(seconds: 3));
        expect(socket.closeCode, WebSocketStatus.policyViolation);
      } finally {
        await subscription?.cancel();
        await socket?.close();
        server.container.dispose();
      }
    },
  );
}
