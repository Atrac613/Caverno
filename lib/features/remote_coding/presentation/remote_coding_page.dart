import 'dart:async';
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
import '../../../core/theme/app_tokens.dart';

class RemoteCodingPage extends ConsumerStatefulWidget {
  const RemoteCodingPage({super.key});

  @override
  ConsumerState<RemoteCodingPage> createState() => _RemoteCodingPageState();
}

class _RemoteQuestionResult {
  const _RemoteQuestionResult({
    required this.selectedOptionIds,
    required this.otherText,
  });

  final List<String> selectedOptionIds;
  final String otherText;
}

class _RemoteCodingPageState extends ConsumerState<RemoteCodingPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _presentedApprovalIds = <String>{};
  final Set<String> _presentedQuestionIds = <String>{};

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
    ref.listen<RemoteCodingQuestion?>(
      remoteCodingClientProvider.select((state) => state.pendingQuestion),
      (previous, next) {
        if (next != null && _presentedQuestionIds.add(next.id)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showQuestionSheet(next);
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
                                  fontFamily: kMonoFontFamily,
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
                          fontFamily: kMonoFontFamily,
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

  Future<void> _showQuestionSheet(RemoteCodingQuestion question) async {
    final selectedIds = <String>{};
    final otherController = TextEditingController();
    final result = await showModalBottomSheet<_RemoteQuestionResult>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return StatefulBuilder(
          builder: (statefulContext, setSheetState) {
            final hasAnswer =
                selectedIds.isNotEmpty ||
                otherController.text.trim().isNotEmpty;
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    16 + MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.help_outline),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              question.question,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (question.help.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          question.help,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final option in question.options)
                                _buildQuestionOptionTile(
                                  theme: theme,
                                  option: option,
                                  selected: selectedIds.contains(option.id),
                                  multiSelect: question.allowMultiple,
                                  onTap: () => setSheetState(() {
                                    if (question.allowMultiple) {
                                      if (!selectedIds.remove(option.id)) {
                                        selectedIds.add(option.id);
                                      }
                                    } else {
                                      selectedIds
                                        ..clear()
                                        ..add(option.id);
                                    }
                                  }),
                                ),
                              if (question.allowOther) ...[
                                const SizedBox(height: 4),
                                TextField(
                                  controller: otherController,
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    hintText: question.otherPlaceholder.isNotEmpty
                                        ? question.otherPlaceholder
                                        : 'Other (type an answer)',
                                    border: const OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setSheetState(() {}),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(sheetContext, null),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: hasAnswer
                                  ? () => Navigator.pop(
                                      sheetContext,
                                      _RemoteQuestionResult(
                                        selectedOptionIds: selectedIds.toList(),
                                        otherText: otherController.text.trim(),
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.send),
                              label: const Text('Send'),
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
      },
    );
    otherController.dispose();

    await ref
        .read(remoteCodingClientProvider.notifier)
        .resolveQuestion(
          questionId: question.id,
          selectedOptionIds: result?.selectedOptionIds ?? const <String>[],
          otherText: result?.otherText ?? '',
          cancelled: result == null,
        );
  }

  Widget _buildQuestionOptionTile({
    required ThemeData theme,
    required RemoteCodingQuestionOption option,
    required bool selected,
    required bool multiSelect,
    required VoidCallback onTap,
  }) {
    final IconData icon = multiSelect
        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
        : (selected ? Icons.radio_button_checked : Icons.radio_button_off);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.65)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label),
                      if (option.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          option.description.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

class RemoteCodingDrawerSection extends ConsumerWidget {
  const RemoteCodingDrawerSection({super.key, required this.closeDrawer});

  final VoidCallback closeDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remoteCodingClientProvider);
    final notifier = ref.read(remoteCodingClientProvider.notifier);

    return Column(
      children: [
        _RemoteDrawerSectionHeader(
          title: 'Projects',
          actions: [
            _RemoteDrawerIconButton(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onPressed: state.isConnected
                  ? () => unawaited(notifier.requestSnapshot())
                  : null,
            ),
          ],
        ),
        Expanded(
          child: !state.isConnected
              ? const _RemoteDrawerEmptyState(
                  message:
                      'Connect to a desktop before selecting remote projects.',
                )
              : state.projects.isEmpty
              ? const _RemoteDrawerEmptyState(
                  message: 'No desktop projects yet.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: state.projects.length,
                  itemBuilder: (context, index) {
                    final project = state.projects[index];
                    return _RemoteProjectThreadGroup(
                      project: project,
                      threads: _remoteThreadsForProject(state, project.id),
                      isSelected: project.id == state.selectedProjectId,
                      selectedThreadId: state.currentConversationId,
                      onProjectSelected: () =>
                          unawaited(notifier.selectProject(project.id)),
                      onCreateThread: () {
                        closeDrawer();
                        unawaited(notifier.createThread(projectId: project.id));
                      },
                      onThreadSelected: (threadId) {
                        closeDrawer();
                        unawaited(notifier.selectConversation(threadId));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RemoteDrawerSectionHeader extends StatelessWidget {
  const _RemoteDrawerSectionHeader({
    required this.title,
    required this.actions,
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _RemoteDrawerIconButton extends StatelessWidget {
  const _RemoteDrawerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      onPressed: onPressed,
    );
  }
}

class _RemoteDrawerEmptyState extends StatelessWidget {
  const _RemoteDrawerEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}

class _RemoteProjectThreadGroup extends StatelessWidget {
  const _RemoteProjectThreadGroup({
    required this.project,
    required this.threads,
    required this.isSelected,
    required this.selectedThreadId,
    required this.onProjectSelected,
    required this.onCreateThread,
    required this.onThreadSelected,
  });

  final RemoteCodingProjectSummary project;
  final List<RemoteCodingThreadSummary> threads;
  final bool isSelected;
  final String? selectedThreadId;
  final VoidCallback onProjectSelected;
  final VoidCallback onCreateThread;
  final ValueChanged<String> onThreadSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RemoteProjectTile(
          project: project,
          isSelected: isSelected,
          onTap: onProjectSelected,
          onCreateThread: onCreateThread,
        ),
        if (isSelected)
          for (final thread in threads)
            _RemoteThreadTile(
              thread: thread,
              isSelected: thread.id == selectedThreadId,
              onTap: () => onThreadSelected(thread.id),
            ),
        if (isSelected && threads.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(52, 4, 16, 8),
            child: Text(
              'No threads yet.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

class _RemoteProjectTile extends StatelessWidget {
  const _RemoteProjectTile({
    required this.project,
    required this.isSelected,
    required this.onTap,
    required this.onCreateThread,
  });

  final RemoteCodingProjectSummary project;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCreateThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('remote-drawer-project-${project.id}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 6),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      leading: Icon(
        Icons.folder_outlined,
        size: 20,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        project.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: project.rootPath.isEmpty
          ? null
          : Text(
              project.rootPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: IconButton(
        icon: const Icon(Icons.add, size: 18),
        tooltip: 'New Thread',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        onPressed: onCreateThread,
      ),
      onTap: onTap,
    );
  }
}

class _RemoteThreadTile extends StatelessWidget {
  const _RemoteThreadTile({
    required this.thread,
    required this.isSelected,
    required this.onTap,
  });

  final RemoteCodingThreadSummary thread;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('remote-drawer-thread-${thread.id}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 52, right: 16),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      title: Text(
        thread.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        _formatRemoteThreadDate(thread.updatedAt),
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _RemoteCodingHeader extends StatelessWidget {
  const _RemoteCodingHeader({required this.state, required this.onRefresh});

  final RemoteCodingClientState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final selectedProject = _selectedRemoteProject(state);
    final selectedThread = _selectedRemoteThread(state);
    final snapshotGeneratedAt = state.snapshotGeneratedAt;
    final updatedLabel = snapshotGeneratedAt == null
        ? null
        : TimeOfDay.fromDateTime(snapshotGeneratedAt.toLocal()).format(context);
    final subtitle = selectedProject == null
        ? (state.projects.isEmpty
              ? 'No desktop projects'
              : 'Choose a project or thread from the menu')
        : selectedThread == null
        ? selectedProject.rootPath
        : selectedThread.title;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.lan_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selectedProject?.name ?? 'Remote Coding',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  updatedLabel == null ? subtitle : '$subtitle - $updatedLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

RemoteCodingProjectSummary? _selectedRemoteProject(
  RemoteCodingClientState state,
) {
  for (final project in state.projects) {
    if (project.id == state.selectedProjectId) {
      return project;
    }
  }
  return null;
}

RemoteCodingThreadSummary? _selectedRemoteThread(
  RemoteCodingClientState state,
) {
  for (final thread in state.threads) {
    if (thread.id == state.currentConversationId) {
      return thread;
    }
  }
  return null;
}

List<RemoteCodingThreadSummary> _remoteThreadsForProject(
  RemoteCodingClientState state,
  String projectId,
) {
  return state.threads
      .where((thread) => thread.projectId == projectId)
      .toList(growable: false);
}

String _formatRemoteThreadDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inDays == 0) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  if (diff.inDays == 1) {
    return 'Yesterday';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} days ago';
  }
  return '${date.month}/${date.day}';
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
