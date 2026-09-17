import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/logger.dart';
import '../../chat/domain/entities/message.dart';
import '../../dashboard/domain/entities/dashboard_stats.dart';
import '../../dashboard/domain/services/dashboard_stats_codec.dart';
import '../data/remote_coding_connection_messages.dart';
import '../data/remote_coding_notification_payload.dart';
import '../data/remote_coding_notification_relay_delegation.dart';
import '../data/remote_coding_notification_relay_pairing.dart';
import '../data/remote_coding_notification_relay_providers.dart';
import '../data/remote_coding_notification_relay_provisioning.dart';
import '../data/remote_coding_protocol.dart';
import '../data/remote_coding_repository.dart';
import '../data/remote_coding_security.dart';
import '../data/remote_coding_websocket_connector.dart';
import '../domain/remote_coding_error_policy.dart';
import '../domain/remote_coding_models.dart';
import '../domain/remote_coding_session_policy.dart';
import '../domain/remote_coding_transport_policy.dart';
import 'remote_coding_platform.dart';

final remoteCodingClientProvider =
    NotifierProvider<RemoteCodingClientNotifier, RemoteCodingClientState>(
      RemoteCodingClientNotifier.new,
    );

enum RemoteCodingBoundCommandOutcome { accepted, queued, refused, unknown }

class RemoteCodingBoundCommandResult {
  const RemoteCodingBoundCommandResult({
    required this.outcome,
    required this.requestId,
    required this.code,
    required this.message,
  });

  final RemoteCodingBoundCommandOutcome outcome;
  final String requestId;
  final String code;
  final String message;

  bool get acknowledged =>
      outcome == RemoteCodingBoundCommandOutcome.accepted ||
      outcome == RemoteCodingBoundCommandOutcome.queued;
}

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
    this.pendingQuestion,
    this.dashboardStatsByRange = const <DashboardRange, DashboardStats>{},
    this.snapshotSequence = 0,
    this.snapshotGeneratedAt,
    this.reconnectAttempt = 0,
    this.nextReconnectAt,
    this.pendingCommandCount = 0,
    this.lastTerminalNotification,
    this.supportsNotificationRelaySetup = false,
    this.supportsDestinationBoundCommands = false,
    this.notificationRelayHandle,
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
  final RemoteCodingQuestion? pendingQuestion;
  final Map<DashboardRange, DashboardStats> dashboardStatsByRange;
  final int snapshotSequence;
  final DateTime? snapshotGeneratedAt;
  final int reconnectAttempt;
  final DateTime? nextReconnectAt;
  final int pendingCommandCount;
  final RemoteCodingNotificationPayload? lastTerminalNotification;

  final bool supportsNotificationRelaySetup;
  final bool supportsDestinationBoundCommands;
  final String? notificationRelayHandle;

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
    RemoteCodingQuestion? pendingQuestion,
    Map<DashboardRange, DashboardStats>? dashboardStatsByRange,
    int? snapshotSequence,
    DateTime? snapshotGeneratedAt,
    int? reconnectAttempt,
    DateTime? nextReconnectAt,
    int? pendingCommandCount,
    RemoteCodingNotificationPayload? lastTerminalNotification,
    bool? supportsNotificationRelaySetup,
    bool? supportsDestinationBoundCommands,
    String? notificationRelayHandle,
    bool clearNotificationRelayHandle = false,
    bool clearError = false,
    bool clearSelectedProjectId = false,
    bool clearCurrentConversationId = false,
    bool clearPendingApproval = false,
    bool clearPendingQuestion = false,
    bool clearSnapshotGeneratedAt = false,
    bool clearNextReconnectAt = false,
    bool clearLastTerminalNotification = false,
  }) {
    return RemoteCodingClientState(
      supportsNotificationRelaySetup:
          supportsNotificationRelaySetup ?? this.supportsNotificationRelaySetup,
      supportsDestinationBoundCommands:
          supportsDestinationBoundCommands ??
          this.supportsDestinationBoundCommands,
      notificationRelayHandle: clearNotificationRelayHandle
          ? null
          : notificationRelayHandle ?? this.notificationRelayHandle,
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
      pendingQuestion: clearPendingQuestion
          ? null
          : (pendingQuestion ?? this.pendingQuestion),
      dashboardStatsByRange:
          dashboardStatsByRange ?? this.dashboardStatsByRange,
      snapshotSequence: snapshotSequence ?? this.snapshotSequence,
      snapshotGeneratedAt: clearSnapshotGeneratedAt
          ? null
          : (snapshotGeneratedAt ?? this.snapshotGeneratedAt),
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      nextReconnectAt: clearNextReconnectAt
          ? null
          : (nextReconnectAt ?? this.nextReconnectAt),
      pendingCommandCount: pendingCommandCount ?? this.pendingCommandCount,
      lastTerminalNotification: clearLastTerminalNotification
          ? null
          : (lastTerminalNotification ?? this.lastTerminalNotification),
    );
  }
}

class RemoteCodingClientNotifier extends Notifier<RemoteCodingClientState> {
  static const Duration _commandTimeout = Duration(seconds: 12);
  static const Duration _socketPingInterval = Duration(seconds: 20);
  /// Delay before each successive automatic reconnect attempt.
  ///
  /// The last entry is a steady state, not a dead end: once the ladder is
  /// walked the client keeps retrying at that interval instead of giving up.
  /// The previous three-rung ladder surrendered after ~22 seconds, which is
  /// shorter than a desktop takes to wake, so the common case -- phone comes
  /// out of a pocket while the desktop is still asleep -- always ended in a
  /// manual tap. A suspended app costs nothing here because the OS does not
  /// fire timers while it is backgrounded.
  static const List<Duration> _reconnectBackoffDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final _uuid = const Uuid();
  late final RemoteCodingRepository _repository;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Completer<bool>? _connectedSnapshotWaiter;
  final Map<String, Timer> _pendingCommandTimers = <String, Timer>{};
  bool _manualDisconnectRequested = false;
  Completer<RemoteCodingSessionChallenge>? _pendingAuthChallenge;
  final _relayReplies = <String, Completer<RemoteCodingProtocolMessage>>{};
  final _boundCommandReplies =
      <String, Completer<RemoteCodingProtocolMessage>>{};

  @override
  RemoteCodingClientState build() {
    _repository = ref.read(remoteCodingRepositoryProvider);
    // Mobile only. A desktop reports `resumed` every time its window regains
    // focus, which is not a signal that the network came back.
    if (isRemoteCodingMobileRuntimePlatform()) {
      final observer = _ForegroundReconnectObserver(
        () => unawaited(connectSavedHostIfIdle()),
      );
      WidgetsBinding.instance.addObserver(observer);
      ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
    }
    ref.onDispose(() {
      _cancelReconnectTimer();
      _completeConnectedSnapshotWaiter(false);
      _clearPendingCommandTimers();
      unawaited(disconnect());
    });
    return RemoteCodingClientState(host: _repository.loadMobileHost());
  }

  /// Connects to the saved host.
  ///
  /// [automatic] keeps the backoff ladder running when this attempt fails;
  /// a manual attempt reports the failure and stops instead.
  ///
  /// [continuingLadder] marks the ladder's own scheduled attempt. Every other
  /// caller is an explicit request -- the Reconnect button, a tapped
  /// notification, a background-woken Watch command -- and re-arms the ladder
  /// from zero. Without that, one exhausted ladder disabled automatic
  /// reconnection for the rest of the session: `reconnectAttempt` fell back to
  /// zero only on a successful snapshot, so a manual retry that also failed
  /// left it at the cap and the next unexpected drop gave up with no attempt
  /// at all.
  Future<void> connectSavedHost({
    bool automatic = false,
    bool continuingLadder = false,
  }) async {
    _manualDisconnectRequested = false;
    if (!continuingLadder) {
      _cancelReconnectTimer();
      state = state.copyWith(
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
    }
    final host = _repository.loadMobileHost();
    if (host == null) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.disconnected,
        error: RemoteCodingConnectionMessages.missingHost(),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      _completeConnectedSnapshotWaiter(false);
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
      _completeConnectedSnapshotWaiter(false);
      return;
    }
    await _connectAndAuth(
      host: host,
      token: token,
      autoReconnectOnFailure: automatic,
    );
  }

  /// Reconnects immediately and waits for an authenticated desktop snapshot.
  ///
  /// `connectSavedHost` returns after the authentication command is written,
  /// which is too early for a background-woken Watch command to trust the
  /// desktop destination. This method waits for `_applySnapshot` instead. It
  /// never replays the command that caused the reconnect.
  Future<bool> reconnectSavedHostAndWait({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (state.isConnected) return true;
    _cancelReconnectTimer();
    final waiter = _connectedSnapshotWaiter ??= Completer<bool>();
    unawaited(_startSavedHostReconnect());
    try {
      return await waiter.future.timeout(
        timeout,
        onTimeout: () {
          _completeConnectedSnapshotWaiter(false);
          return false;
        },
      );
    } finally {
      if (identical(_connectedSnapshotWaiter, waiter)) {
        _connectedSnapshotWaiter = null;
      }
    }
  }

  /// Connects to the saved host when nothing else is already trying.
  ///
  /// Two callers, one situation: the app has come back to the foreground, or
  /// the Remote Coding page has just been opened. Neither reconnected before.
  /// The OS suspends timers while the app is backgrounded, so a ladder meant to
  /// cover a sleeping desktop instead walks its rungs in the seconds after the
  /// phone is unlocked -- against a desktop that has not finished waking -- and
  /// nothing re-armed it afterwards. What was left was the Reconnect button,
  /// and the person had to know to look for it.
  ///
  /// The attempt is automatic, so a failure keeps the backoff ladder running
  /// rather than reporting an error and stopping the way a tap does.
  ///
  /// A manual disconnect is still honoured: that is a decision, not a fault.
  Future<void> connectSavedHostIfIdle() async {
    if (!ref.mounted || _manualDisconnectRequested) return;
    switch (state.status) {
      case RemoteCodingConnectionStatus.connected:
      case RemoteCodingConnectionStatus.connecting:
      case RemoteCodingConnectionStatus.pairing:
        return;
      case RemoteCodingConnectionStatus.disconnected:
      case RemoteCodingConnectionStatus.error:
        break;
    }
    // The published host, not the repository: a notifier whose `build` a test
    // replaced never initialized `_repository`, and reading it here threw out
    // of a post-frame callback where nothing could catch it. `connectSavedHost`
    // still loads the host authoritatively; this is only the guard.
    if (state.host == null) return;
    await connectSavedHost(automatic: true);
  }

  Future<void> _startSavedHostReconnect() async {
    try {
      await connectSavedHost(automatic: true);
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          status: RemoteCodingConnectionStatus.error,
          error: 'Remote coding reconnect failed: $error',
        );
      }
      _completeConnectedSnapshotWaiter(false);
    }
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
        error: error is RemoteCodingPlaintextDowngradeException
            ? error.toString()
            : RemoteCodingConnectionMessages.invalidPairingCode(),
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
      certificatePin: payload.certificatePin,
    );
    await _connectAndAuth(
      host: host,
      ticketId: payload.ticketId,
      secret: payload.secret,
      autoReconnectOnFailure: false,
    );
  }

  /// Complete notification delegation on the authenticated, pinned connection.
  Future<void> authorizeNotificationRelay() async {
    final host = state.host;
    final socket = _socket;
    if (!state.isConnected ||
        host?.certificatePin == null ||
        socket == null ||
        !state.supportsNotificationRelaySetup) {
      throw StateError('This desktop requires the notification QR setup.');
    }
    final registration = await _repository.loadMobileRelayRegistration();
    if (registration != null &&
        registration.expiresAt.isAfter(DateTime.now()) &&
        state.notificationRelayHandle == registration.deliveryHandle) {
      return;
    }
    final reply = await _requestRelayCommand(
      'requestNotificationRelay',
      const {},
    );
    final raw = reply.payload['notificationRelayChallenge'];
    if (raw is! Map<String, dynamic> ||
        raw['targetDeviceId'] != host!.id ||
        raw['kind'] != RemoteCodingNotificationRelayPairingPayload.kind ||
        raw['challengeId'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,256}$',
        ).hasMatch(raw['challengeId'] as String) ||
        raw['challengeDigest'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['challengeDigest'] as String)) {
      throw const FormatException('Invalid notification setup challenge.');
    }
    final expiresAt = DateTime.tryParse(raw['expiresAt'] as String? ?? '');
    if (expiresAt == null ||
        !isRemoteCodingRelayDelegationExpiryAcceptable(
          delegationExpiresAt: expiresAt,
          now: DateTime.now().toUtc(),
        )) {
      throw StateError('Notification setup challenge expired.');
    }
    final relayClient = ref.read(remoteCodingNotificationRelayClientProvider);
    if (relayClient == null) {
      throw StateError('Notification relay is unavailable.');
    }
    final delegation =
        await RemoteCodingMobileRelayDelegationCoordinator(
          repository: _repository,
          relayClient: relayClient,
          clock: DateTime.now,
        ).createDelegation(
          challengeId: raw['challengeId'] as String,
          challengeDigest: raw['challengeDigest'] as String,
          targetDeviceId: host.id,
        );
    if (_socket != socket || state.host?.id != host.id || !state.isConnected) {
      throw StateError(
        'The paired connection changed during notification setup.',
      );
    }
    if (!isRemoteCodingRelayDelegationExpiryAcceptable(
      delegationExpiresAt: delegation.expiresAt,
      now: DateTime.now().toUtc(),
    )) {
      throw StateError('Notification delegation expired.');
    }
    final activated = await _requestRelayCommand(
      'relayDelegationReady',
      RemoteCodingRelayDelegationReadyMessage(
        challengeId: delegation.challengeId,
        delegationId: delegation.delegationId,
        expiresAt: delegation.expiresAt,
      ).toPayload(),
    );
    if (_socket != socket ||
        !state.isConnected ||
        state.host?.id != host.id ||
        activated.payload['notificationRelayHandle'] !=
            registration?.deliveryHandle ||
        registration == null) {
      throw StateError('Desktop notification activation was not confirmed.');
    }
  }

  Future<RemoteCodingProtocolMessage> _requestRelayCommand(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final socket = _socket;
    if (socket == null || !state.isConnected) {
      throw StateError(
        'Connect to the desktop before setting up notifications.',
      );
    }
    final id = _uuid.v4();
    final completer = Completer<RemoteCodingProtocolMessage>();
    _relayReplies[id] = completer;
    try {
      socket.add(
        RemoteCodingProtocol.encode(type: type, id: id, payload: payload),
      );
      final response = await completer.future.timeout(
        const Duration(seconds: 45),
      );
      if (response.type != 'snapshot') {
        throw StateError('Desktop notification setup failed.');
      }
      return response;
    } finally {
      _relayReplies.remove(id);
    }
  }

  Future<void> authorizeNotificationRelayFromQr(String qrData) async {
    try {
      final payload = RemoteCodingNotificationRelayPairingPayload.fromQrData(
        qrData,
      );
      final host = state.host;
      final socket = _socket;
      if (!state.isConnected || host == null) {
        throw StateError(
          'Connect to the paired remote coding desktop before enabling notifications.',
        );
      }
      if (payload.targetDeviceId != host.id) {
        throw StateError(
          'Notification relay code belongs to a different paired device.',
        );
      }
      final now = DateTime.now().toUtc();
      if (!payload.expiresAt.toUtc().isAfter(now)) {
        throw StateError('Notification relay code has expired.');
      }
      final relayClient = ref.read(remoteCodingNotificationRelayClientProvider);
      if (relayClient == null) {
        throw StateError('Notification relay is not configured.');
      }
      final coordinator = RemoteCodingMobileRelayDelegationCoordinator(
        repository: _repository,
        relayClient: relayClient,
        clock: DateTime.now,
      );
      final delegation = await coordinator.createDelegation(
        challengeId: payload.challengeId,
        challengeDigest: payload.challengeDigest,
        targetDeviceId: payload.targetDeviceId,
      );
      if (!isRemoteCodingRelayDelegationExpiryAcceptable(
        delegationExpiresAt: delegation.expiresAt,
        now: now,
      )) {
        throw StateError('Relay returned an invalid delegation expiry.');
      }
      if (_socket != socket ||
          state.host?.id != host.id ||
          !state.isConnected) {
        throw StateError(
          'The paired connection changed during notification setup.',
        );
      }
      await _requestRelayCommand(
        'relayDelegationReady',
        RemoteCodingRelayDelegationReadyMessage(
          challengeId: delegation.challengeId,
          delegationId: delegation.delegationId,
          expiresAt: delegation.expiresAt,
        ).toPayload(),
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnectRequested = true;
    _cancelReconnectTimer();
    _completeConnectedSnapshotWaiter(false);
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
    _failPendingAuthChallenge();
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close(WebSocketStatus.goingAway);
    }
  }

  Future<RemoteCodingSessionChallenge> _awaitAuthChallenge() {
    final pending = _pendingAuthChallenge;
    if (pending == null) {
      throw const RemoteCodingAuthChallengeRequiredException();
    }
    return pending.future.timeout(const Duration(seconds: 8));
  }

  void _completeAuthChallenge(Map<String, dynamic> payload) {
    final pending = _pendingAuthChallenge;
    if (pending == null || pending.isCompleted) {
      return;
    }
    try {
      pending.complete(
        RemoteCodingSessionChallenge.fromPayload(
          payload,
          certificatePin: state.host?.certificatePin ?? '',
        ),
      );
    } catch (error) {
      pending.completeError(error);
    }
  }

  void _failPendingAuthChallenge() {
    final pending = _pendingAuthChallenge;
    _pendingAuthChallenge = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const RemoteCodingAuthChallengeRequiredException());
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

  Future<RemoteCodingBoundCommandResult> sendMessageToConversation({
    required String projectId,
    required String conversationId,
    required String content,
    String languageCode = 'en',
    bool isVoiceMode = false,
  }) {
    return _requestBoundCommand(
      RemoteCodingProtocol.sendMessageToConversation,
      {
        'projectId': projectId,
        'conversationId': conversationId,
        'content': content,
        'languageCode': languageCode,
        'isVoiceMode': isVoiceMode,
      },
    );
  }

  Future<RemoteCodingBoundCommandResult> cancelConversationStreaming({
    required String projectId,
    required String conversationId,
  }) {
    return _requestBoundCommand(
      RemoteCodingProtocol.cancelConversationStreaming,
      {'projectId': projectId, 'conversationId': conversationId},
    );
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

  Future<void> resolveQuestion({
    required String questionId,
    List<String> selectedOptionIds = const <String>[],
    String otherText = '',
    bool cancelled = false,
  }) {
    return _sendCommand('resolveQuestion', {
      'questionId': questionId,
      'cancelled': cancelled,
      if (!cancelled) 'selectedOptionIds': selectedOptionIds,
      if (!cancelled && otherText.trim().isNotEmpty)
        'otherText': otherText.trim(),
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
      _completeConnectedSnapshotWaiter(false);
      return;
    }
    if (!RemoteCodingNetworkPolicy.isLanHost(host.host)) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: RemoteCodingConnectionMessages.nonLanHost(host),
        reconnectAttempt: 0,
        clearNextReconnectAt: true,
      );
      _completeConnectedSnapshotWaiter(false);
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
      final url = host.websocketUrl;
      RemoteCodingTransportPolicy.ensureConfidentialBeforeCredentials(
        url: url,
        certificatePin: host.certificatePin,
      );
      final socket = await connectPinnedRemoteCodingWebSocket(
        url: url,
        certificatePin: host.certificatePin,
      ).timeout(const Duration(seconds: 8));
      socket.pingInterval = _socketPingInterval;
      _socket = socket;
      _pendingAuthChallenge = Completer<RemoteCodingSessionChallenge>();
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
      final challenge = await _awaitAuthChallenge();
      final credential = token ?? secret ?? '';
      final authPayload = <String, dynamic>{
        'deviceName': Platform.localHostname,
        'challengeId': challenge.challengeId,
        'proof': RemoteCodingSessionPolicy.proof(
          credential: credential,
          challengeId: challenge.challengeId,
          nonce: challenge.nonce,
          certificatePin: host.certificatePin,
        ),
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
        _completeConnectedSnapshotWaiter(false);
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
        case 'authChallenge':
          _completeAuthChallenge(message.payload);
        case 'snapshot':
        case 'chatStateChanged':
        case 'projectsChanged':
        case 'conversationsChanged':
        case 'approvalRequested':
        case 'approvalResolved':
        case 'questionRequested':
        case 'questionResolved':
          await _applySnapshot(message.payload);
        case 'runTerminal':
          _handleRunTerminal(message.payload);
        case RemoteCodingProtocol.commandResult:
          break;
        case 'error':
          if (_boundCommandReplies.containsKey(message.id) &&
              message.payload['code'] != 'unauthorized' &&
              !RemoteCodingErrorPolicy.endsTheSession(
                (message.payload['code'] as String?)?.trim() ?? '',
              )) {
            state = state.copyWith(
              error:
                  (message.payload['message'] as String?) ??
                  'Remote coding command was refused.',
            );
          } else {
            await _handleRemoteError(message.payload);
          }
        case 'disconnected':
          await _handleRemoteDisconnect(message.payload);
      }
      final reply = _relayReplies[message.id];
      if (reply != null && !reply.isCompleted) reply.complete(message);
      final boundReply = _boundCommandReplies[message.id];
      if (boundReply != null && !boundReply.isCompleted) {
        boundReply.complete(message);
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
      _completeConnectedSnapshotWaiter(false);
      return;
    }
    if (!ref.mounted) {
      return;
    }
    final message = (payload['message'] as String?) ?? 'Remote coding error.';
    if (RemoteCodingErrorPolicy.endsTheSession(code)) {
      state = state.copyWith(
        status: RemoteCodingConnectionStatus.error,
        error: message,
        isLoading: false,
        queuedCount: 0,
        snapshotSequence: 0,
        clearPendingApproval: true,
        clearSnapshotGeneratedAt: true,
      );
      _completeConnectedSnapshotWaiter(false);
      return;
    }
    // A declined command, over a socket that is still open. Say so and change
    // nothing else; see RemoteCodingErrorPolicy for what that used to cost.
    state = state.copyWith(error: message, isLoading: false);
  }

  void _handleRunTerminal(Map<String, dynamic> payload) {
    state = state.copyWith(
      lastTerminalNotification: RemoteCodingNotificationPayload.fromFcmData(
        payload,
      ),
    );
  }

  void clearLastTerminalNotification() {
    state = state.copyWith(clearLastTerminalNotification: true);
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
      _completeConnectedSnapshotWaiter(false);
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
              certificatePin: currentHost.certificatePin,
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
      final questionJson = payload['pendingQuestion'];
      // The one line that separates "the desktop never told us" from "we were
      // told and did not act". Everything downstream of this — the
      // notification, its actions, the watch — is invisible when it does not
      // happen, and this notifier logged nothing at all before.
      if (state.status != RemoteCodingConnectionStatus.connected ||
          approvalJson != null) {
        appLog(
          '[RemoteCodingClient] snapshot while ${state.status.name}: '
          'pendingApproval=${approvalJson is Map<String, dynamic> ? approvalJson['id'] : 'none'}, '
          'pendingQuestion=${questionJson is Map<String, dynamic> ? 'yes' : 'none'}',
        );
      }
      final dashboardStatsByRange = DashboardStatsCodec.decodeByRange(
        payload['dashboardStatsByRange'],
      );
      state = state.copyWith(
        supportsNotificationRelaySetup:
            (payload['capabilities']
                as Map<String, dynamic>?)?['notificationRelaySetup'] ==
            true,
        supportsDestinationBoundCommands:
            (payload['capabilities']
                as Map<String, dynamic>?)?['destinationBoundCommands'] ==
            true,
        notificationRelayHandle: payload['notificationRelayHandle'] as String?,
        clearNotificationRelayHandle:
            payload['notificationRelayHandle'] == null,
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
        pendingQuestion: questionJson is Map<String, dynamic>
            ? RemoteCodingQuestion.fromJson(questionJson)
            : null,
        dashboardStatsByRange: dashboardStatsByRange,
        snapshotSequence: snapshotSequence != null && snapshotSequence > 0
            ? snapshotSequence
            : null,
        snapshotGeneratedAt: snapshotGeneratedAt,
        reconnectAttempt: 0,
        pendingCommandCount: _pendingCommandTimers.length,
        clearPendingApproval: approvalJson == null,
        clearPendingQuestion: questionJson == null,
        clearError: true,
        clearNextReconnectAt: true,
      );
      _completeConnectedSnapshotWaiter(true);
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

  Future<RemoteCodingBoundCommandResult> _requestBoundCommand(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final socket = _socket;
    final host = state.host;
    final id = _uuid.v4();
    if (socket == null || host == null || !state.isConnected) {
      return RemoteCodingBoundCommandResult(
        outcome: RemoteCodingBoundCommandOutcome.unknown,
        requestId: id,
        code: 'disconnected',
        message: 'The desktop connection is unavailable.',
      );
    }
    if (!state.supportsDestinationBoundCommands) {
      return RemoteCodingBoundCommandResult(
        outcome: RemoteCodingBoundCommandOutcome.refused,
        requestId: id,
        code: 'unsupported_peer',
        message: 'The desktop does not support destination-bound commands.',
      );
    }

    final completer = Completer<RemoteCodingProtocolMessage>();
    _boundCommandReplies[id] = completer;
    _trackPendingCommand(id, type);
    try {
      socket.add(
        RemoteCodingProtocol.encode(type: type, id: id, payload: payload),
      );
      final response = await completer.future.timeout(_commandTimeout);
      if (_socket != socket ||
          state.host?.id != host.id ||
          !state.isConnected) {
        return RemoteCodingBoundCommandResult(
          outcome: RemoteCodingBoundCommandOutcome.unknown,
          requestId: id,
          code: 'connection_changed',
          message: 'The desktop connection changed before acknowledgement.',
        );
      }
      if (response.type == 'error') {
        return RemoteCodingBoundCommandResult(
          outcome: RemoteCodingBoundCommandOutcome.refused,
          requestId: id,
          code: (response.payload['code'] as String?)?.trim() ?? 'refused',
          message:
              (response.payload['message'] as String?)?.trim() ??
              'The desktop refused the command.',
        );
      }
      if (response.type != RemoteCodingProtocol.commandResult ||
          response.payload['command'] != type ||
          response.payload['projectId'] != payload['projectId'] ||
          response.payload['conversationId'] != payload['conversationId']) {
        return RemoteCodingBoundCommandResult(
          outcome: RemoteCodingBoundCommandOutcome.unknown,
          requestId: id,
          code: 'invalid_acknowledgement',
          message: 'The desktop acknowledged a different destination.',
        );
      }
      final outcome = switch (response.payload['outcome']) {
        'accepted' => RemoteCodingBoundCommandOutcome.accepted,
        'queued' => RemoteCodingBoundCommandOutcome.queued,
        _ => RemoteCodingBoundCommandOutcome.unknown,
      };
      return RemoteCodingBoundCommandResult(
        outcome: outcome,
        requestId: id,
        code: outcome == RemoteCodingBoundCommandOutcome.unknown
            ? 'invalid_acknowledgement'
            : '',
        message: outcome == RemoteCodingBoundCommandOutcome.unknown
            ? 'The desktop returned an invalid acknowledgement.'
            : '',
      );
    } on TimeoutException {
      return RemoteCodingBoundCommandResult(
        outcome: RemoteCodingBoundCommandOutcome.unknown,
        requestId: id,
        code: 'timeout',
        message: 'The desktop did not acknowledge the command.',
      );
    } catch (_) {
      return RemoteCodingBoundCommandResult(
        outcome: RemoteCodingBoundCommandOutcome.unknown,
        requestId: id,
        code: 'connection_lost',
        message: 'The desktop connection ended before acknowledgement.',
      );
    } finally {
      _boundCommandReplies.remove(id);
      _clearPendingCommandTimer(id);
    }
  }

  void _handleUnexpectedDisconnect(String message) {
    if (!ref.mounted || _manualDisconnectRequested) {
      return;
    }
    _failPendingAuthChallenge();
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
    final delay = _reconnectBackoffDelays[math.min(
      nextAttempt - 1,
      _reconnectBackoffDelays.length - 1,
    )];
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
        unawaited(connectSavedHost(automatic: true, continuingLadder: true));
      }
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _completeConnectedSnapshotWaiter(bool connected) {
    final waiter = _connectedSnapshotWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete(connected);
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
    for (final reply in _relayReplies.values) {
      if (!reply.isCompleted) {
        reply.completeError(
          StateError('Desktop disconnected during notification setup.'),
        );
      }
    }
    _relayReplies.clear();
    for (final reply in _boundCommandReplies.values) {
      if (!reply.isCompleted) {
        reply.completeError(
          StateError('Desktop disconnected before command acknowledgement.'),
        );
      }
    }
    _boundCommandReplies.clear();
    for (final timer in _pendingCommandTimers.values) {
      timer.cancel();
    }
    _pendingCommandTimers.clear();
    if (ref.mounted) {
      state = state.copyWith(pendingCommandCount: 0);
    }
  }
}

/// Tells the client notifier that the app came back to the foreground.
///
/// `AppLifecycleService` records the state but announces nothing, and a
/// suspended app hears none of the socket errors that would otherwise schedule
/// a reconnect.
final class _ForegroundReconnectObserver with WidgetsBindingObserver {
  _ForegroundReconnectObserver(this._onResumed);

  final void Function() _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }
}
