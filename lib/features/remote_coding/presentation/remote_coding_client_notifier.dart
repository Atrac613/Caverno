import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../chat/domain/entities/message.dart';
import '../data/remote_coding_connection_messages.dart';
import '../data/remote_coding_protocol.dart';
import '../data/remote_coding_repository.dart';
import '../data/remote_coding_security.dart';
import '../domain/remote_coding_models.dart';

final remoteCodingClientProvider =
    NotifierProvider<RemoteCodingClientNotifier, RemoteCodingClientState>(
      RemoteCodingClientNotifier.new,
    );

class RemoteCodingClientState {
  const RemoteCodingClientState({
    this.status = RemoteCodingConnectionStatus.disconnected,
    this.host,
    this.error,
    this.projects = const <RemoteCodingProjectSummary>[],
    this.threads = const <RemoteCodingThreadSummary>[],
    this.messages = const <Message>[],
    this.selectedProjectId,
    this.currentConversationId,
    this.isLoading = false,
    this.queuedCount = 0,
    this.pendingApproval,
    this.snapshotSequence = 0,
    this.snapshotGeneratedAt,
    this.reconnectAttempt = 0,
    this.nextReconnectAt,
    this.pendingCommandCount = 0,
  });

  final RemoteCodingConnectionStatus status;
  final RemoteCodingHost? host;
  final String? error;
  final List<RemoteCodingProjectSummary> projects;
  final List<RemoteCodingThreadSummary> threads;
  final List<Message> messages;
  final String? selectedProjectId;
  final String? currentConversationId;
  final bool isLoading;
  final int queuedCount;
  final RemoteCodingApproval? pendingApproval;
  final int snapshotSequence;
  final DateTime? snapshotGeneratedAt;
  final int reconnectAttempt;
  final DateTime? nextReconnectAt;
  final int pendingCommandCount;

  bool get isConnected => status == RemoteCodingConnectionStatus.connected;
  bool get hasScheduledReconnect => nextReconnectAt != null;

  RemoteCodingClientState copyWith({
    RemoteCodingConnectionStatus? status,
    RemoteCodingHost? host,
    String? error,
    List<RemoteCodingProjectSummary>? projects,
    List<RemoteCodingThreadSummary>? threads,
    List<Message>? messages,
    String? selectedProjectId,
    String? currentConversationId,
    bool? isLoading,
    int? queuedCount,
    RemoteCodingApproval? pendingApproval,
    int? snapshotSequence,
    DateTime? snapshotGeneratedAt,
    int? reconnectAttempt,
    DateTime? nextReconnectAt,
    int? pendingCommandCount,
    bool clearError = false,
    bool clearSelectedProjectId = false,
    bool clearCurrentConversationId = false,
    bool clearPendingApproval = false,
    bool clearSnapshotGeneratedAt = false,
    bool clearNextReconnectAt = false,
  }) {
    return RemoteCodingClientState(
      status: status ?? this.status,
      host: host ?? this.host,
      error: clearError ? null : (error ?? this.error),
      projects: projects ?? this.projects,
      threads: threads ?? this.threads,
      messages: messages ?? this.messages,
      selectedProjectId: clearSelectedProjectId
          ? null
          : (selectedProjectId ?? this.selectedProjectId),
      currentConversationId: clearCurrentConversationId
          ? null
          : (currentConversationId ?? this.currentConversationId),
      isLoading: isLoading ?? this.isLoading,
      queuedCount: queuedCount ?? this.queuedCount,
      pendingApproval: clearPendingApproval
          ? null
          : (pendingApproval ?? this.pendingApproval),
      snapshotSequence: snapshotSequence ?? this.snapshotSequence,
      snapshotGeneratedAt: clearSnapshotGeneratedAt
          ? null
          : (snapshotGeneratedAt ?? this.snapshotGeneratedAt),
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      nextReconnectAt: clearNextReconnectAt
          ? null
          : (nextReconnectAt ?? this.nextReconnectAt),
      pendingCommandCount: pendingCommandCount ?? this.pendingCommandCount,
    );
  }
}

class RemoteCodingClientNotifier extends Notifier<RemoteCodingClientState> {
  static const Duration _commandTimeout = Duration(seconds: 12);
  static const Duration _socketPingInterval = Duration(seconds: 20);
  static const List<Duration> _reconnectBackoffDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  final _uuid = const Uuid();
  late final RemoteCodingRepository _repository;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  final Map<String, Timer> _pendingCommandTimers = <String, Timer>{};
  bool _manualDisconnectRequested = false;

  @override
  RemoteCodingClientState build() {
    _repository = ref.read(remoteCodingRepositoryProvider);
    ref.onDispose(() {
      _cancelReconnectTimer();
      _clearPendingCommandTimers();
      unawaited(disconnect());
    });
    return RemoteCodingClientState(host: _repository.loadMobileHost());
  }

  Future<void> connectSavedHost({bool automatic = false}) async {
    _manualDisconnectRequested = false;
    if (!automatic) {
      _cancelReconnectTimer();
    }
    final host = _repository.loadMobileHost();
    if (host == null) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.disconnected,
        error: RemoteCodingConnectionMessages.missingHost(),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      return;
    }
    final token = await _repository.loadMobileHostToken(host.id);
    if (token == null || token.isEmpty) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.disconnected,
        error: RemoteCodingConnectionMessages.missingSavedToken(host),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      return;
    }
    await _connectAndAuth(
      host: host,
      token: token,
      autoReconnectOnFailure: automatic,
    );
  }

  Future<void> pairFromQr(String qrData) async {
    _manualDisconnectRequested = false;
    _cancelReconnectTimer();
    late final RemoteCodingPairingPayload payload;
    try {
      payload = RemoteCodingPairingPayload.fromQrData(qrData);
    } catch (error) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: RemoteCodingConnectionMessages.invalidPairingCode(),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      return;
    }
    if (payload.expiresAt.isBefore(DateTime.now())) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: RemoteCodingConnectionMessages.expiredPairingCode(),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      return;
    }
    if (!RemoteCodingNetworkPolicy.isLanHost(payload.host)) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: RemoteCodingConnectionMessages.nonLanPairingCode(),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      return;
    }

    final host = RemoteCodingHost(
      id: payload.ticketId,
      name: payload.serverName,
      host: payload.host,
      port: payload.port,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _connectAndAuth(
      host: host,
      ticketId: payload.ticketId,
      secret: payload.secret,
      autoReconnectOnFailure: false,
    );
  }

  Future<void> disconnect() async {
    _manualDisconnectRequested = true;
    _cancelReconnectTimer();
    _clearPendingCommandTimers();
    await _closeSocket();
    if (ref.mounted) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.disconnected,
        isLoading: false,
        queuedCount: 0,
        snapshotSequence: 0,
        reconnectAttempt: 0,
        pendingCommandCount: 0,
        clearPendingApproval: true,
        clearSnapshotGeneratedAt: true,
        clearNextReconnectAt: true,
      );
    }
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close(WebSocketStatus.goingAway);
    }
  }

  Future<void> clearSavedHost() async {
    await disconnect();
    await _repository.clearMobileHost();
    state = const RemoteCodingClientState();
  }

  Future<void> selectProject(String projectId) {
    return _sendCommand('selectProject', {'projectId': projectId});
  }

  Future<void> selectConversation(String conversationId) {
    return _sendCommand('selectConversation', {
      'conversationId': conversationId,
    });
  }

  Future<void> createThread({String? projectId}) {
    final targetProjectId = projectId ?? state.selectedProjectId;
    final payload = <String, dynamic>{};
    if (targetProjectId != null) {
      payload['projectId'] = targetProjectId;
    }
    return _sendCommand('createThread', payload);
  }

  Future<void> sendMessage(String content, {String languageCode = 'en'}) {
    return _sendCommand('sendMessage', {
      'content': content,
      'languageCode': languageCode,
    });
  }

  Future<void> cancelStreaming() {
    return _sendCommand('cancelStreaming', const <String, dynamic>{});
  }

  Future<void> resolveApproval({
    required String approvalId,
    required bool approved,
  }) {
    return _sendCommand('resolveApproval', {
      'approvalId': approvalId,
      'approved': approved,
    });
  }

  Future<void> requestSnapshot() {
    return _sendCommand('requestSnapshot', const <String, dynamic>{});
  }

  Future<void> _connectAndAuth({
    required RemoteCodingHost host,
    String? token,
    String? ticketId,
    String? secret,
    required bool autoReconnectOnFailure,
  }) async {
    if (kIsWeb) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: 'Remote coding mobile client is not available on web.',
      );
      return;
    }
    if (!RemoteCodingNetworkPolicy.isLanHost(host.host)) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: RemoteCodingConnectionMessages.nonLanHost(host),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      return;
    }
    _clearPendingCommandTimers();
    await _closeSocket();
    state = state.copyWith(
      status: token == null
          ? RemoteCodingConnectionStatus.pairing
          : RemoteCodingConnectionStatus.connecting,
      host: host,
      clearError: true,
      clearNextReconnectAt: true,
      pendingCommandCount: 0,
    );

    try {
      final socket = await WebSocket.connect(
        host.websocketUrl,
      ).timeout(const Duration(seconds: 8));
      socket.pingInterval = _socketPingInterval;
      _socket = socket;
      _subscription = socket.listen(
        (raw) => unawaited(_handleRawMessage(raw)),
        onDone: () {
          _handleUnexpectedDisconnect(
            RemoteCodingConnectionMessages.connectionClosed(state.host),
          );
        },
        onError: (Object error) {
          _handleUnexpectedDisconnect(
            RemoteCodingConnectionMessages.connectionFailure(error, host),
          );
        },
      );
      final authPayload = <String, dynamic>{
        'deviceName': Platform.localHostname,
      };
      if (token != null) {
        authPayload['token'] = token;
      }
      if (ticketId != null) {
        authPayload['ticketId'] = ticketId;
      }
      if (secret != null) {
        authPayload['secret'] = secret;
      }
      await _sendCommand('auth', authPayload);
    } catch (error) {
      final message = RemoteCodingConnectionMessages.connectionFailure(
        error,
        host,
      );
      if (autoReconnectOnFailure) {
        _handleUnexpectedDisconnect(message);
      } else {
        state = state.copyWith(
          status: RemoteCodingConnectionStatus.error,
          error: message,
          isLoading: false,
          queuedCount: 0,
          snapshotSequence: 0,
          pendingCommandCount: 0,
          clearPendingApproval: true,
          clearSnapshotGeneratedAt: true,
          clearNextReconnectAt: true,
        );
      }
    }
  }

  Future<void> _handleRawMessage(dynamic raw) async {
    try {
      if (raw is! String) {
        return;
      }
      final message = RemoteCodingProtocolMessage.decode(raw);
      _clearPendingCommandTimer(message.id);
      if (!RemoteCodingProtocol.allowedServerEvents.contains(message.type)) {
        state = state.copyWith(
          status: RemoteCodingConnectionStatus.error,
          error: 'Unsupported remote coding event: ${message.type}',
          isLoading: false,
          queuedCount: 0,
          snapshotSequence: 0,
          clearPendingApproval: true,
          clearSnapshotGeneratedAt: true,
        );
        return;
      }
      switch (message.type) {
        case 'snapshot':
        case 'chatStateChanged':
        case 'projectsChanged':
        case 'conversationsChanged':
        case 'approvalRequested':
        case 'approvalResolved':
          await _applySnapshot(message.payload);
        case 'error':
          await _handleRemoteError(message.payload);
        case 'disconnected':
          await _handleRemoteDisconnect(message.payload);
      }
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: 'Remote coding message handling failed: $error',
        isLoading: false,
        queuedCount: 0,
        snapshotSequence: 0,
        clearPendingApproval: true,
        clearSnapshotGeneratedAt: true,
      );
    }
  }

  Future<void> _handleRemoteError(Map<String, dynamic> payload) async {
    final code = (payload['code'] as String?)?.trim() ?? '';
    if (code == 'unauthorized') {
      _manualDisconnectRequested = true;
      _cancelReconnectTimer();
      _clearPendingCommandTimers();
      await _closeSocket();
      await _repository.clearMobileHost();
      if (ref.mounted) {
        state = RemoteCodingClientState(
          status: RemoteCodingConnectionStatus.error,
          error: RemoteCodingConnectionMessages.unauthorizedToken(),
        );
      }
      return;
    }
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      status: RemoteCodingConnectionStatus.error,
      error: (payload['message'] as String?) ?? 'Remote coding error.',
      isLoading: false,
      queuedCount: 0,
      snapshotSequence: 0,
      clearPendingApproval: true,
      clearSnapshotGeneratedAt: true,
    );
  }

  Future<void> _handleRemoteDisconnect(Map<String, dynamic> payload) async {
    final reason = (payload['reason'] as String?)?.trim() ?? '';
    if (reason == 'revoked') {
      _manualDisconnectRequested = true;
      _cancelReconnectTimer();
      _clearPendingCommandTimers();
      await _closeSocket();
      await _repository.clearMobileHost();
      if (ref.mounted) {
        state = RemoteCodingClientState(
          status: RemoteCodingConnectionStatus.error,
          error: RemoteCodingConnectionMessages.revokedDevice(),
        );
      }
      return;
    }
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      status: RemoteCodingConnectionStatus.disconnected,
      isLoading: false,
      queuedCount: 0,
      snapshotSequence: 0,
      pendingCommandCount: 0,
      clearPendingApproval: true,
      clearSnapshotGeneratedAt: true,
      clearNextReconnectAt: true,
    );
  }

  Future<void> _applySnapshot(Map<String, dynamic> payload) async {
    try {
      final snapshotSequence = (payload['snapshotSequence'] as num?)?.toInt();
      if (snapshotSequence != null &&
          snapshotSequence > 0 &&
          snapshotSequence < state.snapshotSequence) {
        return;
      }
      final snapshotGeneratedAt = DateTime.tryParse(
        (payload['snapshotGeneratedAt'] as String?) ?? '',
      );
      final auth = payload['auth'];
      if (auth is Map<String, dynamic>) {
        final token = (auth['deviceToken'] as String?)?.trim();
        final deviceId = (auth['deviceId'] as String?)?.trim();
        if (token != null &&
            token.isNotEmpty &&
            deviceId != null &&
            deviceId.isNotEmpty) {
          final currentHost = state.host;
          if (currentHost != null) {
            final savedHost = RemoteCodingHost(
              id: deviceId,
              name: (auth['serverName'] as String?) ?? currentHost.name,
              host: currentHost.host,
              port: currentHost.port,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            await _repository.saveMobileHost(savedHost, token);
            state = state.copyWith(host: savedHost);
          }
        }
      }

      final projects =
          (payload['projects'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RemoteCodingProjectSummary.fromJson)
              .where((project) => project.id.isNotEmpty)
              .toList(growable: false);
      final threads =
          (payload['conversations'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RemoteCodingThreadSummary.fromJson)
              .where((thread) => thread.id.isNotEmpty)
              .toList(growable: false);
      final rawSelectedProjectId = (payload['selectedProjectId'] as String?)
          ?.trim();
      final selectedProjectId =
          rawSelectedProjectId != null &&
              rawSelectedProjectId.isNotEmpty &&
              projects.any((project) => project.id == rawSelectedProjectId)
          ? rawSelectedProjectId
          : null;
      final rawCurrentConversationId =
          (payload['currentConversationId'] as String?)?.trim();
      final currentConversationId =
          rawCurrentConversationId != null &&
              rawCurrentConversationId.isNotEmpty &&
              threads.any((thread) => thread.id == rawCurrentConversationId)
          ? rawCurrentConversationId
          : null;
      final messages = currentConversationId == null
          ? const <Message>[]
          : (payload['messages'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>()
                .map(Message.fromJson)
                .toList(growable: false);
      final approvalJson = payload['pendingApproval'];
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.connected,
        projects: projects,
        threads: threads,
        messages: messages,
        selectedProjectId: selectedProjectId,
        currentConversationId: currentConversationId,
        clearSelectedProjectId: selectedProjectId == null,
        clearCurrentConversationId: currentConversationId == null,
        isLoading: payload['isLoading'] == true,
        queuedCount: (payload['queuedCount'] as num?)?.toInt() ?? 0,
        pendingApproval: approvalJson is Map<String, dynamic>
            ? RemoteCodingApproval.fromJson(approvalJson)
            : null,
        snapshotSequence: snapshotSequence != null && snapshotSequence > 0
            ? snapshotSequence
            : null,
        snapshotGeneratedAt: snapshotGeneratedAt,
        reconnectAttempt: 0,
        pendingCommandCount: _pendingCommandTimers.length,
        clearPendingApproval: approvalJson == null,
        clearError: true,
        clearNextReconnectAt: true,
      );
    } catch (error) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: 'Failed to apply remote coding snapshot: $error',
      );
    }
  }

  @visibleForTesting
  Future<void> applySnapshotForTest(Map<String, dynamic> payload) {
    return _applySnapshot(payload);
  }

  @visibleForTesting
  Future<void> handleRawMessageForTest(dynamic raw) {
    return _handleRawMessage(raw);
  }

  @visibleForTesting
  void handleUnexpectedDisconnectForTest(String message) {
    _handleUnexpectedDisconnect(message);
  }

  Future<void> _sendCommand(String type, Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.disconnected,
        error: 'Remote coding host is not connected.',
        pendingCommandCount: _pendingCommandTimers.length,
      );
      return;
    }
    final id = _uuid.v4();
    _trackPendingCommand(id, type);
    socket.add(
      RemoteCodingProtocol.encode(type: type, id: id, payload: payload),
    );
  }

  void _handleUnexpectedDisconnect(String message) {
    if (!ref.mounted || _manualDisconnectRequested) {
      return;
    }
    _socket = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _clearPendingCommandTimers();
    final host = state.host;
    if (host == null) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.disconnected,
        error: message,
        isLoading: false,
        queuedCount: 0,
        snapshotSequence: 0,
        pendingCommandCount: 0,
        clearPendingApproval: true,
        clearSnapshotGeneratedAt: true,
        clearNextReconnectAt: true,
      );
      return;
    }
    _scheduleReconnect(host: host, baseMessage: message);
  }

  void _scheduleReconnect({
    required RemoteCodingHost host,
    required String baseMessage,
  }) {
    _cancelReconnectTimer();
    final nextAttempt = state.reconnectAttempt + 1;
    if (nextAttempt > _reconnectBackoffDelays.length) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.disconnected,
        error: '$baseMessage Reconnect attempts were exhausted.',
        isLoading: false,
        queuedCount: 0,
        snapshotSequence: 0,
        reconnectAttempt: nextAttempt - 1,
        pendingCommandCount: 0,
        clearPendingApproval: true,
        clearSnapshotGeneratedAt: true,
        clearNextReconnectAt: true,
      );
      return;
    }
    final delay = _reconnectBackoffDelays[nextAttempt - 1];
    final nextReconnectAt = DateTime.now().add(delay);
    state = state.copyWith(
      status: RemoteCodingConnectionStatus.disconnected,
      error:
          '$baseMessage Reconnecting to ${host.host}:${host.port} in ${delay.inSeconds} seconds.',
      isLoading: false,
      queuedCount: 0,
      snapshotSequence: 0,
      reconnectAttempt: nextAttempt,
      nextReconnectAt: nextReconnectAt,
      pendingCommandCount: 0,
      clearPendingApproval: true,
      clearSnapshotGeneratedAt: true,
    );
    _reconnectTimer = Timer(delay, () {
      if (ref.mounted && !_manualDisconnectRequested) {
        unawaited(connectSavedHost(automatic: true));
      }
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _trackPendingCommand(String id, String type) {
    _pendingCommandTimers[id]?.cancel();
    _pendingCommandTimers[id] = Timer(_commandTimeout, () {
      _pendingCommandTimers.remove(id);
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        error:
            'Remote coding command "$type" timed out. Refresh the connection or reconnect to the desktop host.',
        pendingCommandCount: _pendingCommandTimers.length,
      );
    });
    state = state.copyWith(pendingCommandCount: _pendingCommandTimers.length);
  }

  void _clearPendingCommandTimer(String? id) {
    if (id == null || id.isEmpty) {
      return;
    }
    final timer = _pendingCommandTimers.remove(id);
    timer?.cancel();
    if (ref.mounted) {
      state = state.copyWith(pendingCommandCount: _pendingCommandTimers.length);
    }
  }

  void _clearPendingCommandTimers() {
    for (final timer in _pendingCommandTimers.values) {
      timer.cancel();
    }
    _pendingCommandTimers.clear();
    if (ref.mounted) {
      state = state.copyWith(pendingCommandCount: 0);
    }
  }
}
