import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/types/workspace_mode.dart';
import '../../chat/domain/entities/coding_project.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/chat_state.dart';
import '../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import '../../dashboard/domain/entities/dashboard_stats.dart';
import '../../dashboard/domain/services/dashboard_stats_calculator.dart';
import '../../dashboard/domain/services/dashboard_stats_codec.dart';
import '../data/remote_coding_pairing_registry.dart';
import '../data/remote_coding_protocol.dart';
import '../data/remote_coding_repository.dart';
import '../data/remote_coding_security.dart';
import '../domain/remote_coding_models.dart';

final remoteCodingServerProvider =
    NotifierProvider<RemoteCodingServerNotifier, RemoteCodingServerState>(
      RemoteCodingServerNotifier.new,
    );

class RemoteCodingServerState {
  const RemoteCodingServerState({
    required this.settings,
    this.isRunning = false,
    this.activeHost,
    this.error,
    this.pairingPayload,
    this.activeConnectionCount = 0,
  });

  final RemoteCodingServerSettings settings;
  final bool isRunning;
  final String? activeHost;
  final String? error;
  final RemoteCodingPairingPayload? pairingPayload;
  final int activeConnectionCount;

  String? get activeUrl {
    final host = activeHost;
    if (host == null || host.isEmpty) return null;
    return 'ws://$host:${settings.port}/ws';
  }

  RemoteCodingServerState copyWith({
    RemoteCodingServerSettings? settings,
    bool? isRunning,
    String? activeHost,
    String? error,
    RemoteCodingPairingPayload? pairingPayload,
    int? activeConnectionCount,
    bool clearError = false,
    bool clearPairingPayload = false,
  }) {
    return RemoteCodingServerState(
      settings: settings ?? this.settings,
      isRunning: isRunning ?? this.isRunning,
      activeHost: activeHost ?? this.activeHost,
      error: clearError ? null : (error ?? this.error),
      pairingPayload: clearPairingPayload
          ? null
          : (pairingPayload ?? this.pairingPayload),
      activeConnectionCount:
          activeConnectionCount ?? this.activeConnectionCount,
    );
  }
}

class RemoteCodingServerNotifier extends Notifier<RemoteCodingServerState> {
  static const Duration _pairingLifetime = Duration(minutes: 5);

  final _uuid = const Uuid();
  final RemoteCodingPairingRegistry _pairingRegistry =
      RemoteCodingPairingRegistry();
  final Set<_RemoteCodingSocketClient> _clients = {};

  late final RemoteCodingRepository _repository;
  HttpServer? _server;
  Timer? _pairingExpiryTimer;
  int _snapshotSequence = 0;
  bool _startInProgress = false;

  @override
  RemoteCodingServerState build() {
    _repository = ref.read(remoteCodingRepositoryProvider);
    final settings = _repository.loadServerSettings();

    ref.listen<CodingProjectsState>(codingProjectsNotifierProvider, (_, _) {
      _broadcastSnapshot('projectsChanged');
    });
    ref.listen<ConversationsState>(conversationsNotifierProvider, (_, _) {
      _broadcastSnapshot('conversationsChanged');
    });
    ref.listen<ChatState>(chatNotifierProvider, (previous, next) {
      final approvalChanged =
          previous?.pendingFileOperation?.id != next.pendingFileOperation?.id ||
          previous?.pendingLocalCommand?.id != next.pendingLocalCommand?.id ||
          previous?.pendingGitCommand?.id != next.pendingGitCommand?.id;
      final questionChanged =
          previous?.pendingAskUserQuestion?.id !=
          next.pendingAskUserQuestion?.id;
      if (approvalChanged) {
        _broadcastSnapshot('approvalRequested');
      } else if (questionChanged) {
        _broadcastSnapshot('questionRequested');
      } else {
        _broadcastSnapshot('chatStateChanged');
      }
    });

    ref.onDispose(() {
      unawaited(_stopServer());
    });

    final initialState = RemoteCodingServerState(settings: settings);
    if (_canRunServer && settings.enabled) {
      unawaited(_startServer(settings.port));
    }
    return initialState;
  }

  bool get _canRunServer =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  Future<void> setEnabled(bool enabled) async {
    final nextSettings = state.settings.copyWith(enabled: enabled);
    await _repository.saveServerSettings(nextSettings);
    state = state.copyWith(settings: nextSettings, clearError: true);
    if (enabled) {
      await _startServer(nextSettings.port);
    } else {
      await _stopServer();
    }
  }

  Future<void> revokeDevice(String deviceId) async {
    final devices = state.settings.pairedDevices
        .where((device) => device.id != deviceId)
        .toList(growable: false);
    final settings = state.settings.copyWith(pairedDevices: devices);
    await _repository.saveServerSettings(settings);
    state = state.copyWith(settings: settings);
    for (final client
        in _clients
            .where((client) => client.deviceId == deviceId)
            .toList(growable: false)) {
      await client.close(notify: true, reason: 'revoked');
    }
  }

  Future<RemoteCodingPairingPayload?> createPairingPayload() async {
    if (!_canRunServer) {
      state = state.copyWith(error: 'Remote coding host is desktop only.');
      return null;
    }
    if (!state.settings.enabled) {
      await setEnabled(true);
    } else if (!state.isRunning) {
      await _startServer(state.settings.port);
    }
    if (!state.isRunning) {
      return null;
    }

    _purgeExpiredTickets();
    final host = state.activeHost ?? await _resolveLanHost() ?? '127.0.0.1';
    final payload = RemoteCodingPairingPayload(
      ticketId: _uuid.v4(),
      secret: RemoteCodingSecurity.randomToken(byteLength: 24),
      host: host,
      port: state.settings.port,
      expiresAt: DateTime.now().add(_pairingLifetime),
      serverName: Platform.localHostname,
    );
    _pairingRegistry.clear();
    _pairingRegistry.add(payload);
    state = state.copyWith(pairingPayload: payload);
    _schedulePairingExpiryTimer();
    return payload;
  }

  void cancelPairingPayload(String ticketId) {
    if (state.pairingPayload?.ticketId != ticketId) {
      return;
    }
    _pairingRegistry.remove(ticketId);
    _pairingExpiryTimer?.cancel();
    _pairingExpiryTimer = null;
    state = state.copyWith(clearPairingPayload: true);
  }

  Future<void> _startServer(int port) async {
    if (!_canRunServer || _server != null || _startInProgress) {
      return;
    }
    _startInProgress = true;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server = server;
      state = state.copyWith(
        isRunning: true,
        activeHost: await _resolveLanHost() ?? '127.0.0.1',
        clearError: true,
      );
      unawaited(_serve(server));
    } catch (error) {
      state = state.copyWith(
        isRunning: false,
        error: 'Failed to start remote coding host: $error',
      );
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> _stopServer() async {
    final server = _server;
    _server = null;
    for (final client in _clients.toList(growable: false)) {
      await client.close();
    }
    _clients.clear();
    _pairingRegistry.clear();
    _pairingExpiryTimer?.cancel();
    _pairingExpiryTimer = null;
    if (server != null) {
      await server.close(force: true);
    }
    if (ref.mounted) {
      state = state.copyWith(
        isRunning: false,
        activeConnectionCount: 0,
        clearPairingPayload: true,
      );
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      final remoteAddress = request.connectionInfo?.remoteAddress;
      if (remoteAddress == null ||
          !RemoteCodingNetworkPolicy.isLanAddress(remoteAddress)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        continue;
      }

      if (request.uri.path == '/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
        await request.response.close();
        continue;
      }

      if (request.uri.path != '/ws' ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      final client = _RemoteCodingSocketClient(socket);
      _clients.add(client);
      _syncActiveConnectionCount();
      unawaited(_handleClient(client));
    }
  }

  Future<void> _handleClient(_RemoteCodingSocketClient client) async {
    try {
      await for (final raw in client.socket) {
        if (raw is! String) {
          client.sendError(
            code: 'invalid_message',
            message: 'Text JSON is required.',
          );
          continue;
        }
        late final RemoteCodingProtocolMessage message;
        try {
          message = RemoteCodingProtocolMessage.decode(raw);
        } catch (error) {
          client.sendError(code: 'invalid_message', message: error.toString());
          continue;
        }
        await _handleMessage(client, message);
      }
    } finally {
      _clients.remove(client);
      _syncActiveConnectionCount();
    }
  }

  Future<void> _handleMessage(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) async {
    if (!RemoteCodingProtocol.allowedClientCommands.contains(message.type)) {
      client.sendError(
        id: message.id,
        code: 'unsupported_command',
        message: 'Unsupported remote coding command: ${message.type}',
      );
      return;
    }

    if (message.type == 'auth') {
      await _handleAuth(client, message);
      return;
    }
    if (!client.isAuthenticated) {
      client.sendError(
        id: message.id,
        code: 'unauthorized',
        message: 'Remote coding client is not authenticated.',
      );
      return;
    }

    switch (message.type) {
      case 'selectProject':
        _handleSelectProject(client, message);
      case 'selectConversation':
        _handleSelectConversation(client, message);
      case 'createThread':
        _handleCreateThread(client, message);
      case 'sendMessage':
        await _handleSendMessage(client, message);
      case 'cancelStreaming':
        ref.read(chatNotifierProvider.notifier).cancelStreaming();
        client.sendSnapshot(id: message.id, payload: _buildSnapshot());
      case 'resolveApproval':
        _handleResolveApproval(client, message);
      case 'resolveQuestion':
        _handleResolveQuestion(client, message);
      case 'requestSnapshot':
        client.sendSnapshot(id: message.id, payload: _buildSnapshot());
    }
  }

  Future<void> _handleAuth(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) async {
    final token = (message.payload['token'] as String?)?.trim();
    if (token != null && token.isNotEmpty) {
      final device = await _authenticateToken(token);
      if (device == null) {
        client.sendError(
          id: message.id,
          code: 'unauthorized',
          message: 'Remote coding token was not recognized.',
        );
        return;
      }
      client.deviceId = device.id;
      _syncActiveConnectionCount();
      client.sendSnapshot(id: message.id, payload: _buildSnapshot());
      return;
    }

    final ticketId = (message.payload['ticketId'] as String?)?.trim() ?? '';
    final secret = (message.payload['secret'] as String?)?.trim() ?? '';
    final deviceName =
        (message.payload['deviceName'] as String?)?.trim().isNotEmpty == true
        ? (message.payload['deviceName'] as String).trim()
        : 'Mobile device';
    final pairing = _pairingRegistry.consume(
      ticketId: ticketId,
      secret: secret,
    );
    if (!pairing.isAccepted) {
      if (state.pairingPayload?.ticketId == ticketId) {
        _pairingExpiryTimer?.cancel();
        _pairingExpiryTimer = null;
        state = state.copyWith(clearPairingPayload: true);
      }
      client.sendError(
        id: message.id,
        code: 'pairing_failed',
        message: 'Pairing code is invalid or expired.',
      );
      return;
    }

    final rawToken = RemoteCodingSecurity.randomToken();
    final now = DateTime.now();
    final device = RemoteCodingPairedDevice(
      id: _uuid.v4(),
      name: deviceName,
      tokenHash: RemoteCodingSecurity.hashToken(rawToken),
      createdAt: now,
      lastSeenAt: now,
    );
    final settings = state.settings.copyWith(
      pairedDevices: [device, ...state.settings.pairedDevices],
    );
    await _repository.saveServerSettings(settings);
    state = state.copyWith(settings: settings, clearPairingPayload: true);
    _pairingExpiryTimer?.cancel();
    _pairingExpiryTimer = null;
    client.deviceId = device.id;
    _syncActiveConnectionCount();
    client.sendSnapshot(
      id: message.id,
      payload: {
        ..._buildSnapshot(),
        'auth': {
          'deviceToken': rawToken,
          'deviceId': device.id,
          'serverName': Platform.localHostname,
        },
      },
    );
  }

  Future<RemoteCodingPairedDevice?> _authenticateToken(String token) async {
    final tokenHash = RemoteCodingSecurity.hashToken(token);
    final now = DateTime.now();
    RemoteCodingPairedDevice? matched;
    final devices = state.settings.pairedDevices
        .map((device) {
          if (RemoteCodingSecurity.constantTimeEquals(
            device.tokenHash,
            tokenHash,
          )) {
            matched = device.copyWith(lastSeenAt: now);
            return matched!;
          }
          return device;
        })
        .toList(growable: false);
    if (matched == null) {
      return null;
    }
    final settings = state.settings.copyWith(pairedDevices: devices);
    await _repository.saveServerSettings(settings);
    state = state.copyWith(settings: settings);
    return matched;
  }

  void _handleSelectProject(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) {
    final projectId = (message.payload['projectId'] as String?)?.trim();
    final project = _findProject(projectId);
    if (project == null) {
      client.sendError(
        id: message.id,
        code: 'project_not_found',
        message: 'Selected coding project does not exist on this desktop.',
      );
      return;
    }
    ref.read(codingProjectsNotifierProvider.notifier).selectProject(project.id);
    ref
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: projectWorkspaceMode,
          projectId: project.id,
          createIfMissing: true,
        );
    client.sendSnapshot(id: message.id, payload: _buildSnapshot());
  }

  void _handleSelectConversation(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) {
    final conversationId = (message.payload['conversationId'] as String?)
        ?.trim();
    final conversation = ref
        .read(conversationsNotifierProvider)
        .conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null ||
        conversation.workspaceMode != projectWorkspaceMode ||
        _findProject(conversation.normalizedProjectId) == null) {
      client.sendError(
        id: message.id,
        code: 'conversation_not_found',
        message: 'Selected coding thread does not exist on this desktop.',
      );
      return;
    }
    final projectId = conversation.normalizedProjectId;
    ref.read(codingProjectsNotifierProvider.notifier).selectProject(projectId);
    ref
        .read(conversationsNotifierProvider.notifier)
        .activateWorkspace(
          workspaceMode: projectWorkspaceMode,
          projectId: projectId,
          createIfMissing: false,
        );
    ref
        .read(conversationsNotifierProvider.notifier)
        .selectConversation(conversation.id);
    client.sendSnapshot(id: message.id, payload: _buildSnapshot());
  }

  void _handleCreateThread(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) {
    final requestedProjectId = (message.payload['projectId'] as String?)
        ?.trim();
    final activeProjectId = ref
        .read(conversationsNotifierProvider)
        .activeProjectId;
    final project = _findProject(requestedProjectId ?? activeProjectId);
    if (project == null) {
      client.sendError(
        id: message.id,
        code: 'project_not_found',
        message: 'Create a coding thread after selecting an existing project.',
      );
      return;
    }
    ref.read(codingProjectsNotifierProvider.notifier).selectProject(project.id);
    ref
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: projectWorkspaceMode,
          projectId: project.id,
        );
    client.sendSnapshot(id: message.id, payload: _buildSnapshot());
  }

  Future<void> _handleSendMessage(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) async {
    final content = (message.payload['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) {
      client.sendError(
        id: message.id,
        code: 'empty_message',
        message: 'Message content is required.',
      );
      return;
    }
    final conversationsState = ref.read(conversationsNotifierProvider);
    final project = _findProject(conversationsState.activeProjectId);
    if (project == null || conversationsState.currentConversation == null) {
      client.sendError(
        id: message.id,
        code: 'project_not_found',
        message: 'Select an existing desktop coding project before sending.',
      );
      return;
    }

    unawaited(
      ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            content,
            languageCode: (message.payload['languageCode'] as String?) ?? 'en',
            bypassPlanMode: true,
            origin: ChatInteractionOrigin.remote,
          ),
    );
    client.sendSnapshot(id: message.id, payload: _buildSnapshot());
  }

  void _handleResolveApproval(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) {
    final approvalId = (message.payload['approvalId'] as String?)?.trim() ?? '';
    final approved = message.payload['approved'] == true;
    final chatState = ref.read(chatNotifierProvider);
    final chatNotifier = ref.read(chatNotifierProvider.notifier);

    if (chatState.pendingFileOperation?.id == approvalId) {
      chatNotifier.resolveFileOperation(id: approvalId, approved: approved);
    } else if (chatState.pendingGitCommand?.id == approvalId) {
      chatNotifier.resolveGitCommand(id: approvalId, approved: approved);
    } else if (chatState.pendingLocalCommand?.id == approvalId) {
      chatNotifier.resolveLocalCommand(
        id: approvalId,
        approval: LocalCommandApproval(approved: approved),
      );
    } else {
      client.sendError(
        id: message.id,
        code: 'approval_not_found',
        message: 'Remote approval request is no longer pending.',
      );
      return;
    }

    client.send(
      type: 'approvalResolved',
      id: message.id,
      payload: {'approvalId': approvalId, 'approved': approved},
    );
    _broadcastSnapshot('approvalResolved');
  }

  void _handleResolveQuestion(
    _RemoteCodingSocketClient client,
    RemoteCodingProtocolMessage message,
  ) {
    final questionId = (message.payload['questionId'] as String?)?.trim() ?? '';
    final chatState = ref.read(chatNotifierProvider);
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final pending = chatState.pendingAskUserQuestion;
    if (pending == null || pending.id != questionId) {
      client.sendError(
        id: message.id,
        code: 'question_not_found',
        message: 'Remote question is no longer pending.',
      );
      return;
    }

    final cancelled = message.payload['cancelled'] == true;
    final answer = cancelled
        ? null
        : _parseRemoteQuestionAnswer(pending, message.payload);
    chatNotifier.resolveAskUserQuestion(id: questionId, answer: answer);

    client.send(
      type: 'questionResolved',
      id: message.id,
      payload: {'questionId': questionId, 'cancelled': cancelled},
    );
    _broadcastSnapshot('questionResolved');
  }

  AskUserQuestionAnswer _parseRemoteQuestionAnswer(
    PendingAskUserQuestion pending,
    Map<String, dynamic> payload,
  ) {
    final selectedIds =
        (payload['selectedOptionIds'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
    final selections = pending.options
        .where((option) => selectedIds.contains(option.id))
        .map(
          (option) => AskUserQuestionSelection(
            id: option.id,
            label: option.label,
            description: option.description,
            preview: option.preview,
          ),
        )
        .toList(growable: false);
    return AskUserQuestionAnswer(
      question: pending.question,
      selectedOptions: selections,
      otherText: (payload['otherText'] as String?)?.trim() ?? '',
    );
  }

  CodingProject? _findProject(String? id) {
    final normalizedId = id?.trim();
    if (normalizedId == null || normalizedId.isEmpty) return null;
    return ref.read(codingProjectsNotifierProvider).findById(normalizedId);
  }

  Map<String, dynamic> _buildSnapshot() {
    final projectsState = ref.read(codingProjectsNotifierProvider);
    final conversationsState = ref.read(conversationsNotifierProvider);
    final chatState = ref.read(chatNotifierProvider);
    final generatedAt = DateTime.now();
    _snapshotSequence += 1;
    final selectedProjectId =
        conversationsState.activeProjectId ?? projectsState.selectedProjectId;
    final visibleConversations = conversationsState.conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == projectWorkspaceMode &&
              conversation.normalizedProjectId == selectedProjectId,
        )
        .toList(growable: false);
    final currentConversation = conversationsState.currentConversation;
    final messages =
        currentConversation?.workspaceMode == projectWorkspaceMode &&
            currentConversation?.normalizedProjectId == selectedProjectId
        ? chatState.messages
        : const <Message>[];
    final dashboardStatsByRange = {
      for (final range in DashboardRange.values)
        range: DashboardStatsCalculator.compute(
          conversations: conversationsState.conversations,
          range: range,
        ),
    };

    return {
      'snapshotSequence': _snapshotSequence,
      'snapshotGeneratedAt': generatedAt.toIso8601String(),
      'protocolVersion': remoteCodingProtocolVersion,
      'server': {
        'activeHost': state.activeHost,
        'activeConnectionCount': state.activeConnectionCount,
        'pairedDeviceCount': state.settings.pairedDevices.length,
      },
      'capabilities': const {
        'projectManagement': false,
        'threadCreation': true,
        'streamCancel': true,
        'mobileApprovals': true,
      },
      'projects': projectsState.projects.map(_projectToJson).toList(),
      'selectedProjectId': selectedProjectId,
      'conversations': visibleConversations.map(_conversationToJson).toList(),
      'currentConversationId': currentConversation?.id,
      'messages': messages.map((message) => message.toJson()).toList(),
      'dashboardStatsByRange': DashboardStatsCodec.encodeByRange(
        dashboardStatsByRange,
      ),
      'isLoading': chatState.isLoading,
      'queuedCount': chatState.queuedMessages.length,
      'pendingApproval': _pendingRemoteApproval(chatState)?.toJson(),
      'pendingQuestion': _pendingRemoteQuestion(chatState)?.toJson(),
    };
  }

  /// Maps a remote-origin `ask_user_question` into the wire model. Mirrors
  /// [_pendingRemoteApproval]'s origin gate so a desktop-initiated question is
  /// not surfaced on a paired device.
  RemoteCodingQuestion? _pendingRemoteQuestion(ChatState chatState) {
    final pending = chatState.pendingAskUserQuestion;
    if (pending == null || pending.origin != ChatInteractionOrigin.remote) {
      return null;
    }
    return RemoteCodingQuestion(
      id: pending.id,
      question: pending.question,
      help: pending.help,
      options: pending.options
          .map(
            (option) => RemoteCodingQuestionOption(
              id: option.id,
              label: option.label,
              description: option.description,
              preview: option.preview,
            ),
          )
          .toList(growable: false),
      allowMultiple: pending.allowMultiple,
      allowOther: pending.allowOther,
      otherPlaceholder: pending.otherPlaceholder,
    );
  }

  RemoteCodingApproval? _pendingRemoteApproval(ChatState chatState) {
    final file = chatState.pendingFileOperation;
    if (file != null && file.origin == ChatInteractionOrigin.remote) {
      return RemoteCodingApproval(
        id: file.id,
        kind: RemoteCodingApprovalKind.file,
        title: file.operation,
        subtitle: file.path,
        detail: file.preview,
        reason: file.reason,
      );
    }

    final local = chatState.pendingLocalCommand;
    if (local != null && local.origin == ChatInteractionOrigin.remote) {
      return RemoteCodingApproval(
        id: local.id,
        kind: RemoteCodingApprovalKind.localCommand,
        title: 'Local Command Approval',
        subtitle: local.workingDirectory,
        detail: local.command,
        reason: local.reason,
        warningTitle: local.warningTitle,
        warningMessage: local.warningMessage,
      );
    }

    final git = chatState.pendingGitCommand;
    if (git != null && git.origin == ChatInteractionOrigin.remote) {
      return RemoteCodingApproval(
        id: git.id,
        kind: RemoteCodingApprovalKind.gitCommand,
        title: 'Git Command Approval',
        subtitle: git.workingDirectory,
        detail: 'git ${git.command}',
        reason: git.reason,
      );
    }

    return null;
  }

  Map<String, dynamic> _projectToJson(CodingProject project) => {
    'id': project.id,
    'name': project.name,
    'rootPath': project.rootPath,
  };

  Map<String, dynamic> _conversationToJson(Conversation conversation) => {
    'id': conversation.id,
    'title': conversation.title == defaultConversationTitle
        ? 'New thread'
        : conversation.title,
    'projectId': conversation.normalizedProjectId,
    'updatedAt': conversation.updatedAt.toIso8601String(),
  };

  void _broadcastSnapshot(String type) {
    if (_clients.isEmpty) return;
    final payload = _buildSnapshot();
    for (final client in _clients.where((client) => client.isAuthenticated)) {
      client.send(type: type, payload: payload);
    }
  }

  void _syncActiveConnectionCount() {
    if (!ref.mounted) {
      return;
    }
    final count = _clients.where((client) => client.isAuthenticated).length;
    if (state.activeConnectionCount == count) {
      return;
    }
    state = state.copyWith(activeConnectionCount: count);
  }

  Future<String?> _resolveLanHost() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (RemoteCodingNetworkPolicy.isLanAddress(address)) {
          return address.address;
        }
      }
    }
    return null;
  }

  void _purgeExpiredTickets() {
    final now = DateTime.now();
    _pairingRegistry.purgeExpired(now: now);
    final current = state.pairingPayload;
    if (current != null && !current.expiresAt.isAfter(now)) {
      _pairingExpiryTimer?.cancel();
      _pairingExpiryTimer = null;
      state = state.copyWith(clearPairingPayload: true);
    }
  }

  void _schedulePairingExpiryTimer() {
    _pairingExpiryTimer?.cancel();
    final payload = state.pairingPayload;
    if (payload == null) {
      _pairingExpiryTimer = null;
      return;
    }
    final delay = payload.expiresAt.difference(DateTime.now());
    _pairingExpiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (ref.mounted) {
        _purgeExpiredTickets();
      }
    });
  }
}

const projectWorkspaceMode = WorkspaceMode.coding;

class _RemoteCodingSocketClient {
  _RemoteCodingSocketClient(this.socket);

  final WebSocket socket;
  String? deviceId;

  bool get isAuthenticated => deviceId != null && deviceId!.isNotEmpty;

  void send({
    required String type,
    required Map<String, dynamic> payload,
    String? id,
  }) {
    socket.add(
      RemoteCodingProtocol.encode(type: type, id: id, payload: payload),
    );
  }

  void sendSnapshot({required Map<String, dynamic> payload, String? id}) {
    send(type: 'snapshot', id: id, payload: payload);
  }

  void sendError({required String code, required String message, String? id}) {
    send(
      type: 'error',
      id: id,
      payload: RemoteCodingProtocol.errorPayload(code: code, message: message),
    );
  }

  Future<void> close({bool notify = false, String? reason}) async {
    if (notify) {
      send(
        type: 'disconnected',
        payload: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );
    }
    await socket.close(WebSocketStatus.goingAway);
  }
}
