import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../remote_coding/presentation/remote_coding_client_notifier.dart';
import '../domain/watch_command.dart';
import '../domain/watch_snapshot.dart';

/// Owns the wrist's browsing position independently of the desktop selection.
/// Selecting a project here never invokes the desktop's thread-creating path.
class WatchRemoteNavigation {
  WatchRemoteNavigation({
    required this.readRemote,
    required this.selectConversation,
    required this.onChanged,
    this.selectionTimeout = const Duration(seconds: 12),
  });

  final RemoteCodingClientState Function() readRemote;
  final Future<void> Function(String) selectConversation;
  final void Function() onChanged;
  final Duration selectionTimeout;
  String source = 'local';
  String _sessionId = const Uuid().v4();
  String? _projectId;
  int _offset = 0;
  String? _conversationId;
  String _selectionStatus = 'none';
  int _selectionSequence = 0;
  Completer<bool>? _pendingSelection;

  void update(RemoteCodingClientState? previous, RemoteCodingClientState next) {
    if (previous?.host?.id != next.host?.id ||
        previous?.host?.host != next.host?.host ||
        previous?.host?.port != next.host?.port ||
        previous?.host?.certificatePin != next.host?.certificatePin ||
        previous?.isConnected != next.isConnected) {
      _sessionId = const Uuid().v4();
      _projectId = null;
      _offset = 0;
      _clearSelection();
      return;
    }
    if (_projectId != null && !next.projects.any((p) => p.id == _projectId)) {
      _clearSelection();
      _selectionStatus = 'project_removed';
      return;
    }
    if (_conversationId == null) return;
    if (!next.threads.any(
      (t) => t.id == _conversationId && t.projectId == _projectId,
    )) {
      _clearSelection();
      _selectionStatus = 'thread_removed';
    } else if (next.snapshotSequence > _selectionSequence &&
        next.currentConversationId == _conversationId &&
        next.selectedProjectId == _projectId) {
      _selectionStatus = 'selected';
      _finishSelection(true);
    } else if (_selectionStatus == 'selected') {
      // Do not silently follow another surface to a different conversation.
      _selectionStatus = 'changed';
    }
  }

  WatchRemoteBrowser snapshot() {
    final remote = readRemote();
    final project = remote.projects
        .where((p) => p.id == _projectId)
        .firstOrNull;
    final items = !remote.isConnected
        ? <WatchRemoteItem>[]
        : _projectId == null
        ? remote.projects
              .map((p) => WatchRemoteItem(id: p.id, title: p.name))
              .toList()
        : remote.threads
              .where((t) => project != null && t.projectId == _projectId)
              .map((t) => WatchRemoteItem(id: t.id, title: _title(t.title)))
              .toList();
    final offset = items.isEmpty
        ? 0
        : _offset.clamp(
            0,
            ((items.length - 1) ~/ watchRemotePageSize) * watchRemotePageSize,
          );
    final thread = remote.threads
        .where((t) => t.id == _conversationId)
        .firstOrNull;
    return WatchRemoteBrowser(
      hostId: remote.host?.id ?? '',
      hostName: remote.host?.name.trim().isNotEmpty == true
          ? remote.host!.name
          : remote.host?.host ?? 'Desktop',
      sessionId: _sessionId,
      connectionStatus: remote.host == null ? 'unpaired' : remote.status.name,
      projectId: _projectId,
      projectTitle: project?.name ?? '',
      items: items.skip(offset).take(watchRemotePageSize).toList(),
      offset: offset,
      total: items.length,
      conversationId: _conversationId,
      conversationTitle: thread == null ? '' : _title(thread.title),
      selectionStatus: _selectionStatus,
      supportsInput: remote.supportsDestinationBoundCommands,
    );
  }

  WatchCommandResult validateSelectedDestination(WatchCommand command) {
    final payload = command.payload;
    final remote = readRemote();
    if (source != 'remote' || payload['source'] != 'remote') {
      return _failure(
        command,
        'source_changed',
        'The displayed conversation source changed. Try again.',
      );
    }
    if (!remote.isConnected) {
      return _failure(
        command,
        'remote_disconnected',
        'Reconnect to the desktop before sending.',
      );
    }
    if (payload['hostId'] != remote.host?.id ||
        payload['sessionId'] != _sessionId) {
      return _failure(
        command,
        'remote_changed',
        'The desktop connection changed. Open the thread again.',
      );
    }
    if (!remote.supportsDestinationBoundCommands) {
      return _failure(
        command,
        'unsupported_peer',
        'Update the desktop before sending from Apple Watch.',
      );
    }
    final projectId = payload['projectId'] as String?;
    final conversationId = payload['conversationId'] as String?;
    if (_selectionStatus != 'selected' ||
        projectId == null ||
        conversationId == null ||
        projectId != _projectId ||
        conversationId != _conversationId ||
        remote.selectedProjectId != projectId ||
        remote.currentConversationId != conversationId) {
      return _failure(
        command,
        'destination_changed',
        'The selected desktop thread changed. Open it again.',
      );
    }
    return WatchCommandResult.success(id: command.id);
  }

  /// Restores only a destination already confirmed by the reconnect snapshot.
  ///
  /// This deliberately does not select or switch the desktop conversation.
  /// A delayed Watch command may wake the phone long after it was composed, so
  /// changing the desktop to match that stale command would be a redirect. The
  /// caller can offer an explicit retry only when the fresh snapshot still
  /// names the exact project and conversation.
  bool restoreConfirmedDestination({
    required String projectId,
    required String conversationId,
  }) {
    final remote = readRemote();
    if (!remote.isConnected ||
        remote.selectedProjectId != projectId ||
        remote.currentConversationId != conversationId ||
        !remote.projects.any((project) => project.id == projectId) ||
        !remote.threads.any(
          (thread) =>
              thread.id == conversationId && thread.projectId == projectId,
        )) {
      return false;
    }
    source = 'remote';
    _projectId = projectId;
    _offset = 0;
    _conversationId = conversationId;
    _selectionSequence = remote.snapshotSequence;
    _selectionStatus = 'selected';
    onChanged();
    return true;
  }

  Future<WatchCommandResult> handle(WatchCommand command) async {
    final payload = command.payload;
    if (command.type == WatchCommand.selectSource) {
      if (payload['source'] != 'local') {
        return _failure(
          command,
          'invalid_source',
          'Choose local chats or a paired host.',
        );
      }
      source = 'local';
      _clearSelection();
      onChanged();
      return WatchCommandResult.success(id: command.id);
    }
    final remote = readRemote();
    if (!remote.isConnected) {
      return _failure(
        command,
        'remote_disconnected',
        'Connect to the host on iPhone.',
      );
    }
    if (payload['hostId'] != remote.host?.id ||
        payload['sessionId'] != _sessionId) {
      return _failure(
        command,
        'remote_changed',
        'The host connection changed. Open its projects again.',
      );
    }
    final projectId = payload['projectId'] as String?;
    if (projectId != null && !remote.projects.any((p) => p.id == projectId)) {
      return _failure(
        command,
        'project_not_found',
        'That project no longer exists.',
      );
    }
    if (command.type == WatchCommand.browseRemote) {
      final offset = payload['offset'] ?? 0;
      if (offset is! int || offset < 0 || offset % watchRemotePageSize != 0) {
        return _failure(command, 'invalid_page', 'That page is unavailable.');
      }
      if (_projectId != projectId || source != 'remote') _clearSelection();
      source = 'remote';
      _projectId = projectId;
      _offset = offset;
      onChanged();
      return WatchCommandResult.success(id: command.id);
    }
    final conversationId = payload['conversationId'] as String?;
    if (projectId == null ||
        conversationId == null ||
        !remote.threads.any(
          (t) => t.id == conversationId && t.projectId == projectId,
        )) {
      return _failure(
        command,
        'conversation_not_found',
        'That thread no longer exists in this project.',
      );
    }
    if (_pendingSelection != null) {
      return _failure(
        command,
        'selection_pending',
        'Wait for the current selection.',
      );
    }
    source = 'remote';
    _projectId = projectId;
    _conversationId = conversationId;
    _selectionSequence = remote.snapshotSequence;
    _selectionStatus = 'selecting';
    final pending = Completer<bool>();
    _pendingSelection = pending;
    onChanged();
    try {
      await selectConversation(conversationId);
      final accepted = await pending.future.timeout(
        selectionTimeout,
        onTimeout: () => false,
      );
      if (!accepted ||
          source != 'remote' ||
          _selectionStatus != 'selected' ||
          _sessionId != payload['sessionId']) {
        if (identical(_pendingSelection, pending) &&
            _selectionStatus == 'selecting') {
          _selectionStatus = 'unconfirmed';
        }
        return _failure(
          command,
          'selection_unconfirmed',
          'The host has not confirmed this thread. Open it again.',
        );
      }
      return WatchCommandResult.success(id: command.id);
    } catch (_) {
      _selectionStatus = 'unconfirmed';
      return _failure(
        command,
        'selection_failed',
        'The thread could not be opened.',
      );
    } finally {
      if (identical(_pendingSelection, pending)) _pendingSelection = null;
      onChanged();
    }
  }

  void _clearSelection() {
    _finishSelection(false);
    _conversationId = null;
    _selectionStatus = 'none';
  }

  void _finishSelection(bool accepted) {
    final pending = _pendingSelection;
    if (pending != null && !pending.isCompleted) pending.complete(accepted);
  }

  void dispose() => _finishSelection(false);

  WatchCommandResult _failure(
    WatchCommand command,
    String code,
    String message,
  ) => WatchCommandResult.failure(id: command.id, code: code, message: message);

  String _title(String title) => title == '__new_conversation__' ? '' : title;
}
