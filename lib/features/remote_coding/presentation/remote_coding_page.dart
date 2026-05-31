import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../chat/presentation/widgets/message_bubble.dart';
import '../../settings/presentation/pages/qr_scanner_page.dart';
import '../data/remote_coding_connection_messages.dart';
import '../data/remote_coding_diagnostics.dart';
import '../data/remote_coding_support_packet.dart';
import '../domain/remote_coding_models.dart';
import 'remote_coding_client_notifier.dart';

class RemoteCodingPage extends ConsumerStatefulWidget {
  const RemoteCodingPage({super.key});

  @override
  ConsumerState<RemoteCodingPage> createState() => _RemoteCodingPageState();
}

class _RemoteCodingPageState extends ConsumerState<RemoteCodingPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _presentedApprovalIds = <String>{};

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RemoteCodingApproval?>(
      remoteCodingClientProvider.select((state) => state.pendingApproval),
      (previous, next) {
        if (next != null && _presentedApprovalIds.add(next.id)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showApprovalSheet(next);
            }
          });
        }
      },
    );
    ref.listen<int>(
      remoteCodingClientProvider.select((state) => state.messages.length),
      (previous, next) {
        if ((previous ?? 0) < next) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToLatestMessage();
          });
        }
      },
    );

    final state = ref.watch(remoteCodingClientProvider);
    final notifier = ref.read(remoteCodingClientProvider.notifier);

    if (!state.isConnected) {
      return _RemoteConnectionView(
        state: state,
        onScanPairingCode: _scanPairingCode,
        onReconnect: notifier.connectSavedHost,
        onForget: notifier.clearSavedHost,
        onCopySupportPacket: () => _copyClientSupportPacket(state),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        children: [
          _RemoteCodingHeader(
            state: state,
            onProjectSelected: notifier.selectProject,
            onThreadSelected: notifier.selectConversation,
            onCreateThread: notifier.createThread,
            onRefresh: notifier.requestSnapshot,
          ),
          if (state.error?.isNotEmpty == true)
            _RemoteStatusBanner(
              message: state.error!,
              onCopySupportPacket: () => _copyClientSupportPacket(state),
            ),
          const Divider(height: 1),
          if (state.projects.isEmpty)
            const Expanded(child: _RemoteEmptyProjectsView())
          else
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: state.messages.length,
                itemBuilder: (context, index) {
                  return MessageBubble(message: state.messages[index]);
                },
              ),
            ),
          if (state.queuedCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${state.queuedCount} queued message(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          _RemoteComposer(
            controller: _controller,
            isLoading: state.isLoading,
            enabled: state.projects.isNotEmpty,
            onSend: () => _send(notifier),
            onCancel: notifier.cancelStreaming,
          ),
        ],
      ),
    );
  }

  Future<void> _scanPairingCode() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(
          title: 'Scan Pairing Code',
          hint: 'Point your camera at the desktop pairing QR',
        ),
      ),
    );
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    await ref.read(remoteCodingClientProvider.notifier).pairFromQr(raw);
  }

  Future<void> _send(RemoteCodingClientNotifier notifier) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await notifier.sendMessage(
      text,
      languageCode: Localizations.localeOf(context).languageCode,
    );
  }

  void _scrollToLatestMessage() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _showApprovalSheet(RemoteCodingApproval approval) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final detail = approval.detail.length > 3000
            ? '${approval.detail.substring(0, 3000)}\n...'
            : approval.detail;
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                16 + MediaQuery.of(sheetContext).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_approvalIcon(approval.kind)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              approval.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (approval.subtitle.isNotEmpty)
                              Text(
                                approval.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (approval.reason?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text(approval.reason!),
                  ],
                  if (approval.warningTitle?.isNotEmpty == true ||
                      approval.warningMessage?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text(
                      approval.warningTitle ?? 'High risk command',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    if (approval.warningMessage?.isNotEmpty == true)
                      Text(approval.warningMessage!),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        detail,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.block),
                          label: const Text('Deny'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.check),
                          label: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    await ref
        .read(remoteCodingClientProvider.notifier)
        .resolveApproval(approvalId: approval.id, approved: approved ?? false);
  }

  Future<void> _copyClientSupportPacket(RemoteCodingClientState state) async {
    final diagnostics = RemoteCodingDiagnostics.clientSnapshot(
      status: state.status,
      host: state.host,
      snapshotSequence: state.snapshotSequence,
      snapshotGeneratedAt: state.snapshotGeneratedAt,
      reconnectAttempt: state.reconnectAttempt,
      nextReconnectAt: state.nextReconnectAt,
      pendingCommandCount: state.pendingCommandCount,
      isLoading: state.isLoading,
      queuedCount: state.queuedCount,
      hasPendingApproval: state.pendingApproval != null,
      error: state.error,
    );
    final supportPacket = RemoteCodingSupportPacket.build(
      side: RemoteCodingSupportPacketSide.mobile,
      diagnostics: diagnostics,
    );
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(supportPacket),
      ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Remote coding support packet copied.')),
    );
  }

  IconData _approvalIcon(RemoteCodingApprovalKind kind) {
    return switch (kind) {
      RemoteCodingApprovalKind.file => Icons.edit_note,
      RemoteCodingApprovalKind.localCommand => Icons.terminal,
      RemoteCodingApprovalKind.gitCommand => Icons.account_tree,
    };
  }
}

class _RemoteConnectionView extends StatelessWidget {
  const _RemoteConnectionView({
    required this.state,
    required this.onScanPairingCode,
    required this.onReconnect,
    required this.onForget,
    required this.onCopySupportPacket,
  });

  final RemoteCodingClientState state;
  final VoidCallback onScanPairingCode;
  final VoidCallback onReconnect;
  final VoidCallback onForget;
  final VoidCallback onCopySupportPacket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = state.host;
    final isBusy =
        state.status == RemoteCodingConnectionStatus.connecting ||
        state.status == RemoteCodingConnectionStatus.pairing;
    final statusText = switch (state.status) {
      RemoteCodingConnectionStatus.connecting => 'Connecting to desktop...',
      RemoteCodingConnectionStatus.pairing => 'Pairing with desktop...',
      _ => null,
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phonelink_lock,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Remote Coding',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan the pairing QR from Caverno desktop to control coding projects on your LAN.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (host != null) ...[
              const SizedBox(height: 16),
              Text(
                '${host.name} (${host.host}:${host.port})',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (state.error?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Text(
                state.error!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              _RemoteTroubleshootingCard(
                steps: RemoteCodingConnectionMessages.recoverySteps(
                  host: host,
                  error: state.error,
                ),
              ),
            ],
            if (statusText != null) ...[
              const SizedBox(height: 16),
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 8),
              Text(statusText, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isBusy ? null : onScanPairingCode,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Pair with Desktop'),
            ),
            if (host != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: isBusy ? null : onReconnect,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onCopySupportPacket,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy Support Packet'),
              ),
              TextButton(
                onPressed: isBusy ? null : onForget,
                child: const Text('Forget Host'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemoteStatusBanner extends StatelessWidget {
  const _RemoteStatusBanner({
    required this.message,
    required this.onCopySupportPacket,
  });

  final String message;
  final VoidCallback onCopySupportPacket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.42),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy Support Packet',
            onPressed: onCopySupportPacket,
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }
}

class _RemoteTroubleshootingCard extends StatelessWidget {
  const _RemoteTroubleshootingCard({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.errorContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connection checks',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RemoteCodingHeader extends StatelessWidget {
  const _RemoteCodingHeader({
    required this.state,
    required this.onProjectSelected,
    required this.onThreadSelected,
    required this.onCreateThread,
    required this.onRefresh,
  });

  final RemoteCodingClientState state;
  final ValueChanged<String> onProjectSelected;
  final ValueChanged<String> onThreadSelected;
  final VoidCallback onCreateThread;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final projectValue =
        state.projects.any((project) => project.id == state.selectedProjectId)
        ? state.selectedProjectId
        : null;
    final projectIds = state.projects.map((project) => project.id).join('|');
    final threadValue =
        state.threads.any((thread) => thread.id == state.currentConversationId)
        ? state.currentConversationId
        : null;
    final threadIds = state.threads.map((thread) => thread.id).join('|');
    final snapshotGeneratedAt = state.snapshotGeneratedAt;
    final updatedLabel = snapshotGeneratedAt == null
        ? null
        : TimeOfDay.fromDateTime(snapshotGeneratedAt.toLocal()).format(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('remote-project-$projectIds-$projectValue'),
                  initialValue: projectValue,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Project',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: state.projects
                      .map(
                        (project) => DropdownMenuItem(
                          value: project.id,
                          child: Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onProjectSelected(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'remote-thread-$projectValue-$threadIds-$threadValue',
                  ),
                  initialValue: threadValue,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Thread',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: state.threads
                      .map(
                        (thread) => DropdownMenuItem(
                          value: thread.id,
                          child: Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onThreadSelected(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: state.selectedProjectId == null
                    ? null
                    : onCreateThread,
                icon: const Icon(Icons.add),
                tooltip: 'New Thread',
              ),
            ],
          ),
          if (updatedLabel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Updated $updatedLabel',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoteEmptyProjectsView extends StatelessWidget {
  const _RemoteEmptyProjectsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('No desktop projects', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Add an existing coding project on the desktop app, then refresh this screen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteComposer extends StatelessWidget {
  const _RemoteComposer({
    required this.controller,
    required this.isLoading,
    required this.enabled,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool isLoading;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Message remote coding host',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: !enabled ? null : (isLoading ? onCancel : onSend),
              icon: Icon(isLoading ? Icons.stop : Icons.send),
              tooltip: isLoading ? 'Stop' : 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
