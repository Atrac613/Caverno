import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/types/assistant_mode.dart';
import '../../../core/utils/attachment_format.dart';
import '../../chat/domain/entities/conversation_plan_artifact.dart';
import '../../chat/domain/services/pending_approval_summary.dart';
import '../../chat/presentation/pages/approval_dialog_presenter.dart';
import '../../chat/presentation/providers/custom_slash_commands_notifier.dart';
import '../../chat/presentation/slash_commands/slash_command.dart';
import '../../chat/presentation/slash_commands/slash_command_catalog.dart';
import '../../chat/presentation/slash_commands/slash_command_prompt_template.dart';
import '../../chat/presentation/widgets/approval/approval_dialog_route.dart';
import '../../chat/presentation/widgets/composer_attachment_button.dart';
import '../../chat/presentation/widgets/composer_control_chip.dart';
import '../../chat/presentation/widgets/composer_model_selector.dart';
import '../../chat/presentation/widgets/message_bubble.dart';
import '../../chat/presentation/widgets/message_input_control_labels.dart';
import '../../chat/presentation/widgets/message_input_slash_suggestion_list.dart';
import '../../chat/presentation/widgets/plan/plan_review_sheet.dart';
import '../../chat/presentation/widgets/slash_command_help_sheet.dart';
import '../../chat/presentation/widgets/thread_scroll_to_bottom_button.dart';
import '../../settings/presentation/pages/qr_scanner_page.dart';
import '../data/remote_coding_connection_messages.dart';
import '../data/remote_coding_diagnostics.dart';
import '../data/remote_coding_support_packet.dart';
import '../domain/remote_coding_attachment.dart';
import '../domain/remote_coding_debug_pairing_policy.dart';
import '../domain/remote_coding_models.dart';
import 'remote_coding_attachment_picker.dart';
import 'remote_coding_client_notifier.dart';
import 'remote_coding_companion_panel.dart';
import 'remote_coding_mobile_notification_notifier.dart';
import 'remote_coding_platform.dart';

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
  // Text layout on phone-sized viewports can leave a fractional pixel at the
  // end of a scroll extent. Treat that rounding residue as the bottom.
  static const double _scrollBottomEpsilon = 1;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final ValueNotifier<bool> _showScrollToBottomButton = ValueNotifier<bool>(
    false,
  );
  final _attachmentPicker = const RemoteCodingAttachmentPicker();
  RemoteCodingAttachmentDraft? _attachment;
  bool _isAttachmentBusy = false;

  /// Opens each sheet once and closes it again when the interaction is
  /// answered or withdrawn elsewhere. Shared with the chat page rather than
  /// reimplemented: it removes the exact approval route, which stops a
  /// mistimed dismissal from closing an unrelated screen.
  final ApprovalDialogPresenter _approvalDialogs = ApprovalDialogPresenter();
  final Set<String> _handledNotificationTapEventIds = <String>{};

  /// Captured while the page is mounted, because `ref` cannot be read from
  /// `dispose` — it throws a `StateError` there, which left the suppression
  /// flag below stuck on and silenced the notification for the rest of the
  /// session. It also aborted `dispose` before the controllers were released.
  RemoteCodingMobileNotificationNotifier? _notifications;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollToBottomButtonVisibility);
    // This page raises its own approval sheet, so while it is on screen a
    // notification would ask the same question twice. The notifier cannot
    // infer that from any state it holds, so the page says so itself.
    if (isRemoteCodingMobileRuntimePlatform()) {
      _notifications = ref.read(
        remoteCodingMobileNotificationProvider.notifier,
      );
      _notifications!.setRemoteCodingPageVisible(true);
    }
    // Opening this page with a saved host used to show a Reconnect button and
    // wait to be tapped, even when the only thing wrong was a socket the OS
    // had closed while the app was away. Connecting here is what the tap did.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(remoteCodingClientProvider.notifier).connectSavedHostIfIdle(),
      );
    });
  }

  @override
  void dispose() {
    _notifications?.setRemoteCodingPageVisible(false);
    _controller.dispose();
    _scrollController.removeListener(_updateScrollToBottomButtonVisibility);
    _scrollController.dispose();
    _showScrollToBottomButton.dispose();
    super.dispose();
  }

  void _updateScrollToBottomButtonVisibility() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final visible =
        position.maxScrollExtent - position.pixels > _scrollBottomEpsilon;
    if (_showScrollToBottomButton.value != visible) {
      _showScrollToBottomButton.value = visible;
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0) {
      _updateScrollToBottomButtonVisibility();
    }
    return false;
  }

  void _scheduleScrollToBottomButtonVisibilityUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateScrollToBottomButtonVisibility();
      }
    });
  }

  void _schedulePendingPrompts(RemoteCodingClientState state) {
    if (!state.isConnected) return;
    final approval = state.pendingApproval;
    if (approval != null) {
      _scheduleApprovalSheet(approval);
    }
    final question = state.pendingQuestion;
    if (question != null) {
      _scheduleQuestionSheet(question);
    }
    final planReview = state.pendingPlanReview;
    if (planReview != null) {
      _schedulePlanReviewSheet(planReview);
    }
  }

  /// Opens a sheet for something that was already pending when this page
  /// appeared. `previous: null` because there is nothing to dismiss on this
  /// path; the listeners in `build` own the closing half, and the presenter
  /// opens each id once whichever path reaches it first.
  void _scheduleApprovalSheet(RemoteCodingApproval approval) {
    _approvalDialogs.sync<RemoteCodingApproval>(
      context: context,
      previous: null,
      next: approval,
      idOf: (approval) => approval.id,
      present: _showApprovalSheet,
      isMounted: () => mounted,
    );
  }

  void _scheduleQuestionSheet(RemoteCodingQuestion question) {
    _approvalDialogs.sync<RemoteCodingQuestion>(
      context: context,
      previous: null,
      next: question,
      idOf: (question) => question.id,
      present: _showQuestionSheet,
      isMounted: () => mounted,
    );
  }

  void _schedulePlanReviewSheet(RemoteCodingPlanReview review) {
    _approvalDialogs.sync<RemoteCodingPlanReview>(
      context: context,
      previous: null,
      next: review,
      idOf: (review) => review.id,
      present: _showPlanReviewSheet,
      isMounted: () => mounted,
    );
  }

  void _scheduleNotificationTap(RemoteCodingMobileNotificationState state) {
    final notification = state.pendingNotificationTap;
    if (notification == null ||
        !_handledNotificationTapEventIds.add(notification.eventId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_openNotificationTarget(notification.conversationId));
      }
    });
  }

  Future<void> _openNotificationTarget(String conversationId) async {
    final clientNotifier = ref.read(remoteCodingClientProvider.notifier);
    try {
      if (!ref.read(remoteCodingClientProvider).isConnected) {
        await clientNotifier.connectSavedHost();
      }
      if (ref.read(remoteCodingClientProvider).isConnected) {
        await clientNotifier.selectConversation(conversationId);
      }
    } finally {
      if (mounted) {
        ref
            .read(remoteCodingMobileNotificationProvider.notifier)
            .clearPendingNotificationTap();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Opening and closing both go through the presenter the watch already
    // needed (WATCH6). This page only opened: nothing took a sheet away when
    // the interaction it asks about stopped being pending, so answering at the
    // desktop, or withdrawing the grant that let this device see it at all,
    // left the phone still asking — and answering it then was refused.
    ref.listen<RemoteCodingApproval?>(
      remoteCodingClientProvider.select((state) => state.pendingApproval),
      (previous, next) => _approvalDialogs.sync<RemoteCodingApproval>(
        context: context,
        previous: previous,
        next: next,
        idOf: (approval) => approval.id,
        present: _showApprovalSheet,
        isMounted: () => mounted,
      ),
    );
    ref.listen<RemoteCodingQuestion?>(
      remoteCodingClientProvider.select((state) => state.pendingQuestion),
      (previous, next) => _approvalDialogs.sync<RemoteCodingQuestion>(
        context: context,
        previous: previous,
        next: next,
        idOf: (question) => question.id,
        present: _showQuestionSheet,
        isMounted: () => mounted,
      ),
    );
    ref.listen<RemoteCodingPlanReview?>(
      remoteCodingClientProvider.select((state) => state.pendingPlanReview),
      (previous, next) => _approvalDialogs.sync<RemoteCodingPlanReview>(
        context: context,
        previous: previous,
        next: next,
        idOf: (review) => review.id,
        present: _showPlanReviewSheet,
        isMounted: () => mounted,
      ),
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
    final notificationState = ref.watch(remoteCodingMobileNotificationProvider);
    final customSlashCommandTemplates = ref.watch(
      customSlashCommandsNotifierProvider,
    );
    _scheduleNotificationTap(notificationState);
    _schedulePendingPrompts(state);
    _scheduleScrollToBottomButtonVisibilityUpdate();
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

    final selectedProject = _selectedRemoteProject(state);
    final isDraftComposer =
        selectedProject != null && state.currentConversationId == null;
    final slashCommands = buildSlashCommandCatalog(
      text: _resolveSlashCommandText,
      customPromptTemplates: customSlashCommandTemplates,
    );
    final composer = _RemoteComposer(
      controller: _controller,
      isLoading: state.isLoading,
      enabled: state.projects.isNotEmpty,
      supportsAttachments: state.supportsAttachments,
      attachment: _attachment,
      isAttachmentBusy: _isAttachmentBusy,
      composerSettings: state.composerSettings,
      slashCommands: slashCommands,
      onSlashCommand: (invocation) => _handleSlashCommand(
        invocation,
        isLoading: state.isLoading,
        customPromptTemplates: customSlashCommandTemplates,
        projectId: selectedProject?.id,
      ),
      onSend: () => _send(notifier),
      onCancel: notifier.cancelStreaming,
      onLoadModels: notifier.loadComposerModels,
      onComposerSettingsChanged: (selection) => notifier.updateComposerSettings(
        model: selection.model,
        reasoningEffort: selection.reasoningEffort,
        enableThinking: selection.enableThinking,
        assistantMode:
            state.composerSettings?.assistantMode ?? AssistantMode.coding,
      ),
      onAssistantModeSelected: (mode) {
        final settings = state.composerSettings;
        if (settings == null) return;
        unawaited(
          notifier.updateComposerSettings(
            model: settings.model,
            reasoningEffort: settings.reasoningEffort,
            enableThinking: settings.enableThinking,
            assistantMode: mode,
          ),
        );
      },
      assistantMode:
          state.composerSettings?.assistantMode ?? AssistantMode.coding,
      onPickImage: _pickImage,
      onPickFile: _pickFile,
      onClearAttachment: _clearAttachment,
      onPaste: _handlePaste,
      onContentInserted: _handleContentInserted,
    );

    return SafeArea(
      top: false,
      child: Column(
        children: [
          _RemoteCodingHeader(
            state: state,
            notificationState: notificationState,
            onOpenCompanion: state.selectedProjectId == null
                ? null
                : () => unawaited(_showCompanionPanel()),
            onRefresh: notifier.requestSnapshot,
            onEnableNotifications: _enableCompletionNotifications,
            onDisableNotifications: () => ref
                .read(remoteCodingMobileNotificationProvider.notifier)
                .disable(),
          ),
          if (!notificationState.isEnabled &&
              notificationState.message?.isNotEmpty == true)
            _MobileNotificationStatusBanner(
              state: notificationState,
              onRetry: _enableCompletionNotifications,
            ),
          if (state.error?.isNotEmpty == true)
            _RemoteStatusBanner(
              message: state.error!,
              onCopySupportPacket: () => _copyClientSupportPacket(state),
            ),
          const Divider(height: 1),
          if (state.projects.isEmpty)
            const Expanded(child: _RemoteEmptyProjectsView())
          else if (isDraftComposer)
            Expanded(
              child: _RemoteCodingDraftComposer(
                projectName: selectedProject.name,
                composer: composer,
              ),
            )
          else
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        return MessageBubble(message: state.messages[index]);
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _showScrollToBottomButton,
                      builder: (context, visible, child) {
                        if (!visible) {
                          return const SizedBox.shrink();
                        }
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: child,
                          ),
                        );
                      },
                      child: ThreadScrollToBottomButton(
                        onPressed: _scrollToLatestMessage,
                      ),
                    ),
                  ],
                ),
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
          if (!isDraftComposer) composer,
        ],
      ),
    );
  }

  /// Debug-only, and read once so the whole page shares one answer.
  static final _debugPairingPolicy = RemoteCodingDebugPairingPolicy.current();

  Future<void> _scanPairingCode() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScannerPage(
          title: 'Scan Pairing Code',
          hint: 'Point your camera at the desktop pairing QR',
          allowManualEntry: _debugPairingPolicy.allowsManualPairingEntry,
        ),
      ),
    );
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    await ref.read(remoteCodingClientProvider.notifier).pairFromQr(raw);
  }

  Future<bool> _scanNotificationRelayCode() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScannerPage(
          title: 'Enable Completion Notifications',
          hint: 'Scan the notification QR shown by the connected desktop',
          allowManualEntry: _debugPairingPolicy.allowsManualPairingEntry,
        ),
      ),
    );
    if (raw == null || raw.trim().isEmpty) {
      return false;
    }
    await ref
        .read(remoteCodingClientProvider.notifier)
        .authorizeNotificationRelayFromQr(raw);
    return true;
  }

  Future<void> _enableCompletionNotifications() async {
    await ref
        .read(remoteCodingMobileNotificationProvider.notifier)
        .enable(
          authorizeDesktop: () async {
            if (!mounted) return false;
            final client = ref.read(remoteCodingClientProvider);
            if (client.supportsNotificationRelaySetup &&
                client.host?.certificatePin != null) {
              await ref
                  .read(remoteCodingClientProvider.notifier)
                  .authorizeNotificationRelay();
              return true;
            }
            return _scanNotificationRelayCode();
          },
        );
  }

  Future<void> _pickImage() async {
    await _applyPickedAttachment(_attachmentPicker.pickImage());
  }

  Future<void> _pickFile() async {
    await _applyPickedAttachment(_attachmentPicker.pickFile());
  }

  Future<void> _applyPickedAttachment(
    Future<RemoteCodingAttachmentDraft?> pending,
  ) async {
    if (_isAttachmentBusy) return;
    setState(() => _isAttachmentBusy = true);
    try {
      final attachment = await pending;
      if (!mounted || attachment == null) return;
      _setAttachment(attachment);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add attachment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAttachmentBusy = false);
    }
  }

  void _setAttachment(RemoteCodingAttachmentDraft attachment) {
    if (attachment.bytes.length > RemoteCodingAttachmentPolicy.maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attachments must be ${RemoteCodingAttachmentPolicy.maxSizeLabel} '
            'or smaller.',
          ),
        ),
      );
      return;
    }
    setState(() => _attachment = attachment);
  }

  void _clearAttachment() {
    setState(() => _attachment = null);
  }

  Future<void> _handlePaste() async {
    if (_isAttachmentBusy) return;
    setState(() => _isAttachmentBusy = true);
    try {
      final attachment = await _attachmentPicker.readClipboard();
      if (mounted && attachment != null) {
        _setAttachment(attachment);
        return;
      }
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final pastedText = clipData?.text;
      if (mounted && pastedText != null && pastedText.isNotEmpty) {
        final selection = _controller.selection;
        final text = _controller.text;
        final start = selection.isValid ? selection.start : text.length;
        final end = selection.isValid ? selection.end : text.length;
        final nextText = text.replaceRange(start, end, pastedText);
        _controller.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: start + pastedText.length),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not paste attachment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAttachmentBusy = false);
    }
  }

  Future<void> _handleContentInserted(KeyboardInsertedContent content) async {
    await _applyPickedAttachment(
      _attachmentPicker.fromInsertedContent(content),
    );
  }

  String _resolveSlashCommandText(
    String key, {
    Map<String, String>? namedArgs,
  }) => key.tr(namedArgs: namedArgs);

  Future<SlashCommandExecutionResult> _handleSlashCommand(
    SlashCommandInvocation invocation, {
    required bool isLoading,
    required List<SlashCommandPromptTemplate> customPromptTemplates,
    required String? projectId,
  }) async {
    if (isLoading && !invocation.definition.enabledWhileLoading) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_blocked_while_loading'.tr(),
      );
    }

    final notifier = ref.read(remoteCodingClientProvider.notifier);
    final currentSettings = ref
        .read(remoteCodingClientProvider)
        .composerSettings;
    switch (invocation.definition.action) {
      case SlashCommandAction.help:
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SlashCommandHelpSheet(
            title: 'chat.slash_commands_title'.tr(),
            commands: buildSlashCommandCatalog(
              text: _resolveSlashCommandText,
              customPromptTemplates: customPromptTemplates,
            ),
          ),
        );
        return SlashCommandExecutionResult.handled;
      case SlashCommandAction.newConversation:
        if (projectId == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'chat.slash_new_thread_started'.tr(),
          );
        }
        await notifier.createThread(projectId: projectId);
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_new_thread_started'.tr(),
        );
      case SlashCommandAction.clear:
        await notifier.clearConversation();
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_cleared'.tr(),
        );
      case SlashCommandAction.general:
      case SlashCommandAction.coding:
      case SlashCommandAction.plan:
        final mode = switch (invocation.definition.action) {
          SlashCommandAction.general => AssistantMode.general,
          SlashCommandAction.coding => AssistantMode.coding,
          SlashCommandAction.plan => AssistantMode.plan,
          _ => AssistantMode.coding,
        };
        if (currentSettings == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'The desktop composer settings are unavailable.',
          );
        }
        await notifier.updateComposerSettings(
          model: currentSettings.model,
          reasoningEffort: currentSettings.reasoningEffort,
          enableThinking: currentSettings.enableThinking,
          assistantMode: mode,
        );
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_mode_changed'.tr(
            namedArgs: {'mode': messageInputAssistantModeLabel(mode)},
          ),
        );
      case SlashCommandAction.cancel:
        if (!isLoading) {
          return SlashCommandExecutionResult(
            feedbackMessage: 'chat.slash_cancel_idle'.tr(),
          );
        }
        await notifier.cancelStreaming();
        return SlashCommandExecutionResult(
          feedbackMessage: 'chat.slash_cancelled'.tr(),
        );
      case SlashCommandAction.review:
      case SlashCommandAction.fix:
      case SlashCommandAction.explain:
      case SlashCommandAction.test:
      case SlashCommandAction.promptTemplate:
        final template = resolveSlashCommandPromptTemplate(
          invocation,
          customPromptTemplates,
        );
        if (template == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: 'message.slash_command_failed'.tr(),
          );
        }
        return SlashCommandExecutionResult.sendPrompt(
          template.expand(
            args: invocation.args,
            commandName: invocation.commandName,
          ),
        );
      case SlashCommandAction.pro:
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage: 'chat.slash_pro_unavailable'.tr(),
        );
      case SlashCommandAction.goal:
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage: 'chat.slash_goal_unavailable'.tr(),
        );
      case SlashCommandAction.feedback:
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage:
              'Feedback submission is available from the desktop composer.',
        );
      case SlashCommandAction.worktreeAgent:
        return SlashCommandExecutionResult.keepInput(
          feedbackMessage: 'chat.slash_agent_unavailable'.tr(),
        );
    }
  }

  Future<void> _send(RemoteCodingClientNotifier notifier) async {
    final text = _controller.text.trim();
    final attachment = _attachment;
    if (text.isEmpty && attachment == null) return;
    final sent = await notifier.sendMessage(
      text,
      attachment: attachment,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (!mounted || !sent) return;
    _controller.clear();
    setState(() => _attachment = null);
  }

  Future<void> _showCompanionPanel() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return Consumer(
          builder: (context, ref, _) {
            final liveState = ref.watch(remoteCodingClientProvider);
            return FractionallySizedBox(
              heightFactor: 0.82,
              child: RemoteCodingCompanionPanel(
                snapshot: liveState.companion,
                isLoading: liveState.isLoading,
                queuedCount: liveState.queuedCount,
                pendingQuestion: liveState.pendingQuestion?.question,
              ),
            );
          },
        );
      },
    );
  }

  void _scrollToLatestMessage() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    _showScrollToBottomButton.value = false;
    unawaited(
      _scrollController
          .animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          )
          .then((_) {
            if (mounted) {
              _updateScrollToBottomButtonVisibility();
            }
          }),
    );
  }

  Future<void> _showApprovalSheet(RemoteCodingApproval approval) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      routeSettings: RouteSettings(name: approvalDialogRouteName(approval.id)),
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final detail = approval.detail.length > 3000
            ? '${approval.detail.substring(0, 3000)}\n...'
            : approval.detail;
        return DecoratedBox(
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
                  // A kind that needs structured input — SSH credentials,
                  // computer-use smoke arming — cannot be finished here, and
                  // the desktop refuses such a resolution anyway. Say so,
                  // rather than showing a button that would be rejected or,
                  // worse, one that answers a question it did not ask.
                  if (!approval.isSimpleDecision)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This request needs input that only the '
                                'desktop can collect. Finish it there.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Without this the sheet is a trap: it offers no
                        // answer, the modal is not dismissible by design so a
                        // stray tap cannot resolve an approval, and the phone
                        // then waits on the desktop to act before it can do
                        // anything else. Closing resolves nothing -- the
                        // caller returns early for a kind it cannot answer --
                        // and the sheet comes back if it is still pending when
                        // the page is next shown.
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                          label: const Text('Close'),
                        ),
                      ],
                    )
                  else
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

    // Closing a read-only sheet is not a denial. The sheet showed no buttons,
    // so `approved` is necessarily null here, and sending `false` would refuse
    // a request the person was told to finish on the desktop — and would be
    // rejected there anyway, since the desktop resolves simple decisions only.
    if (!approval.isSimpleDecision) return;

    await ref
        .read(remoteCodingClientProvider.notifier)
        .resolveApproval(approvalId: approval.id, approved: approved ?? false);
  }

  Future<void> _showQuestionSheet(RemoteCodingQuestion question) async {
    final selectedIds = <String>{};
    final otherController = TextEditingController();
    final result = await showModalBottomSheet<_RemoteQuestionResult>(
      context: context,
      routeSettings: RouteSettings(name: approvalDialogRouteName(question.id)),
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
            return DecoratedBox(
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
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetContext).size.height * 0.84,
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
                                      hintText:
                                          question.otherPlaceholder.isNotEmpty
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
                                          selectedOptionIds: selectedIds
                                              .toList(),
                                          otherText: otherController.text
                                              .trim(),
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

  Future<void> _showPlanReviewSheet(RemoteCodingPlanReview review) async {
    final action = await showModalBottomSheet<PlanReviewSheetAction>(
      context: context,
      routeSettings: RouteSettings(name: approvalDialogRouteName(review.id)),
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.96,
          child: PlanReviewSheet(
            planArtifact: ConversationPlanArtifact(
              draftMarkdown: review.draftMarkdown,
              approvedMarkdown: review.approvedMarkdown,
            ),
            isPlanMode: review.isPlanMode,
            canApprove: review.canApprove,
            canCancel: review.canCancel,
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    final actionName = switch (action) {
      PlanReviewSheetAction.approve => 'approve',
      PlanReviewSheetAction.edit => 'edit',
      PlanReviewSheetAction.cancel => 'cancel',
    };
    await ref
        .read(remoteCodingClientProvider.notifier)
        .resolvePlanReview(
          reviewId: review.id,
          action: actionName,
          languageCode: Localizations.localeOf(context).languageCode,
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

  /// An icon for a wire approval kind.
  ///
  /// The kind is a free-form string, so the default has to stand for "an
  /// approval whose kind this build does not know" rather than resembling one
  /// of the kinds it does. A generic warning glyph says that honestly; picking
  /// the closest-looking icon would not.
  IconData _approvalIcon(String kind) {
    return switch (kind) {
      PendingApprovalKinds.file => Icons.edit_note,
      PendingApprovalKinds.localCommand => Icons.terminal,
      PendingApprovalKinds.gitCommand => Icons.account_tree,
      PendingApprovalKinds.sshCommand ||
      PendingApprovalKinds.sshConnect => Icons.dns_outlined,
      PendingApprovalKinds.browserAction => Icons.public,
      PendingApprovalKinds.computerUse => Icons.desktop_windows_outlined,
      PendingApprovalKinds.bleConnect => Icons.bluetooth,
      PendingApprovalKinds.serialOpen => Icons.cable,
      PendingApprovalKinds.participantTool => Icons.groups_outlined,
      PendingApprovalKinds.assumptionConfirmation => Icons.help_outline,
      _ => Icons.warning_amber_outlined,
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

class RemoteCodingDrawerSection extends ConsumerStatefulWidget {
  const RemoteCodingDrawerSection({super.key, required this.closeDrawer});

  final VoidCallback closeDrawer;

  @override
  ConsumerState<RemoteCodingDrawerSection> createState() =>
      _RemoteCodingDrawerSectionState();
}

class _RemoteCodingDrawerSectionState
    extends ConsumerState<RemoteCodingDrawerSection> {
  static const int _collapsedProjectThreadLimit = 5;

  final Set<String> _expandedProjectIds = <String>{};
  final Set<String> _collapsedProjectIds = <String>{};

  void _toggleProjectExpanded(String projectId) {
    setState(() {
      if (!_expandedProjectIds.add(projectId)) {
        _expandedProjectIds.remove(projectId);
      }
    });
  }

  void _handleProjectTapped(
    RemoteCodingClientState state,
    RemoteCodingClientNotifier notifier,
    String projectId,
  ) {
    if (projectId == state.selectedProjectId) {
      setState(() {
        if (!_collapsedProjectIds.add(projectId)) {
          _collapsedProjectIds.remove(projectId);
        }
      });
      return;
    }

    setState(() {
      _collapsedProjectIds.remove(projectId);
    });
    unawaited(notifier.selectProject(projectId));
  }

  @override
  Widget build(BuildContext context) {
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: state.projects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final project = state.projects[index];
                    final isSelected = project.id == state.selectedProjectId;
                    final isCollapsed = _collapsedProjectIds.contains(
                      project.id,
                    );
                    return _RemoteProjectThreadGroup(
                      project: project,
                      threads: _remoteThreadsForProject(state, project.id),
                      isSelected: isSelected,
                      isThreadListVisible: isSelected && !isCollapsed,
                      isExpanded: _expandedProjectIds.contains(project.id),
                      collapsedThreadLimit: _collapsedProjectThreadLimit,
                      selectedThreadId: state.currentConversationId,
                      onProjectSelected: () =>
                          _handleProjectTapped(state, notifier, project.id),
                      onToggleExpanded: () =>
                          _toggleProjectExpanded(project.id),
                      onCreateThread: () {
                        widget.closeDrawer();
                        unawaited(notifier.createThread(projectId: project.id));
                      },
                      onThreadSelected: (threadId) {
                        widget.closeDrawer();
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
    required this.isThreadListVisible,
    required this.isExpanded,
    required this.collapsedThreadLimit,
    required this.selectedThreadId,
    required this.onProjectSelected,
    required this.onToggleExpanded,
    required this.onCreateThread,
    required this.onThreadSelected,
  });

  final RemoteCodingProjectSummary project;
  final List<RemoteCodingThreadSummary> threads;
  final bool isSelected;
  final bool isThreadListVisible;
  final bool isExpanded;
  final int collapsedThreadLimit;
  final String? selectedThreadId;
  final VoidCallback onProjectSelected;
  final VoidCallback onToggleExpanded;
  final VoidCallback onCreateThread;
  final ValueChanged<String> onThreadSelected;

  @override
  Widget build(BuildContext context) {
    final visibleThreads = !isThreadListVisible
        ? const <RemoteCodingThreadSummary>[]
        : isExpanded
        ? threads
        : threads.take(collapsedThreadLimit).toList(growable: false);
    final hiddenThreadCount = threads.length - collapsedThreadLimit;

    return Column(
      spacing: 4,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RemoteProjectTile(
          project: project,
          isSelected: isSelected,
          onTap: onProjectSelected,
          onCreateThread: onCreateThread,
        ),
        for (final thread in visibleThreads)
          _RemoteThreadTile(
            thread: thread,
            isSelected: thread.id == selectedThreadId,
            onTap: () => onThreadSelected(thread.id),
          ),
        if (isThreadListVisible && threads.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(52, 4, 16, 8),
            child: Text(
              'No threads yet.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        if (isThreadListVisible && hiddenThreadCount > 0)
          _RemoteShowMoreThreadsTile(
            projectId: project.id,
            isExpanded: isExpanded,
            onTap: onToggleExpanded,
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

class _RemoteShowMoreThreadsTile extends StatelessWidget {
  const _RemoteShowMoreThreadsTile({
    required this.projectId,
    required this.isExpanded,
    required this.onTap,
  });

  final String projectId;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('remote-drawer-project-$projectId-show-more'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 52, right: 16),
      title: Text(
        isExpanded ? 'Show less' : 'Show more',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
      onTap: onTap,
    );
  }
}

class _RemoteCodingHeader extends StatelessWidget {
  const _RemoteCodingHeader({
    required this.state,
    required this.notificationState,
    required this.onOpenCompanion,
    required this.onRefresh,
    required this.onEnableNotifications,
    required this.onDisableNotifications,
  });

  final RemoteCodingClientState state;
  final RemoteCodingMobileNotificationState notificationState;
  final VoidCallback? onOpenCompanion;
  final VoidCallback onRefresh;
  final VoidCallback onEnableNotifications;
  final VoidCallback onDisableNotifications;

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
            key: const ValueKey('remote-coding-companion-action'),
            onPressed: onOpenCompanion,
            icon: const Icon(Icons.view_sidebar_outlined),
            tooltip: 'Toggle companion panel',
          ),
          if (notificationState.isEnabled ||
              notificationState.status ==
                  RemoteCodingMobileNotificationStatus.registered ||
              notificationState.status ==
                  RemoteCodingMobileNotificationStatus.error)
            PopupMenuButton<String>(
              tooltip: notificationState.isEnabled
                  ? 'Completion notifications enabled'
                  : 'Completion notification settings',
              icon: const Icon(Icons.notifications_active_outlined),
              onSelected: (value) {
                if (value == 'replace') {
                  onEnableNotifications();
                } else if (value == 'disable') {
                  onDisableNotifications();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'replace',
                  child: Text(
                    notificationState.isEnabled
                        ? 'Check notification setup'
                        : 'Finish notification setup',
                  ),
                ),
                const PopupMenuItem(
                  value: 'disable',
                  child: Text('Disable notifications'),
                ),
              ],
            )
          else
            IconButton(
              onPressed:
                  notificationState.status ==
                      RemoteCodingMobileNotificationStatus.enabling
                  ? null
                  : onEnableNotifications,
              icon: Icon(
                notificationState.status ==
                        RemoteCodingMobileNotificationStatus.denied
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
              ),
              tooltip:
                  notificationState.message ??
                  'Enable completion notifications',
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

class _MobileNotificationStatusBanner extends StatelessWidget {
  const _MobileNotificationStatusBanner({
    required this.state,
    required this.onRetry,
  });

  final RemoteCodingMobileNotificationState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.notifications_none, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.message ?? 'Completion notifications are unavailable.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (state.canRetry)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
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

class _RemoteCodingDraftComposer extends StatelessWidget {
  const _RemoteCodingDraftComposer({
    required this.projectName,
    required this.composer,
  });

  final String projectName;
  final Widget composer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'chat.coding_draft_prompt'.tr(
                  namedArgs: {'project': projectName},
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              composer,
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteAssistantModeSelector extends StatelessWidget {
  const _RemoteAssistantModeSelector({
    required this.enabled,
    required this.assistantMode,
    required this.onSelected,
  });

  final bool enabled;
  final AssistantMode assistantMode;
  final ValueChanged<AssistantMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: PopupMenuButton<AssistantMode>(
        enabled: enabled,
        tooltip: 'message.mode_tooltip'.tr(),
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final mode in AssistantMode.values)
            CheckedPopupMenuItem<AssistantMode>(
              value: mode,
              checked: assistantMode == mode,
              child: Text(messageInputAssistantModeLabel(mode)),
            ),
        ],
        child: buildComposerControlChip(
          theme: theme,
          icon: Icons.tune,
          label: messageInputAssistantModeLabel(assistantMode),
          key: const ValueKey('remote-assistant-mode-selector'),
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
    required this.supportsAttachments,
    required this.attachment,
    required this.isAttachmentBusy,
    required this.composerSettings,
    required this.assistantMode,
    required this.slashCommands,
    required this.onSlashCommand,
    required this.onAssistantModeSelected,
    required this.onSend,
    required this.onCancel,
    required this.onLoadModels,
    required this.onComposerSettingsChanged,
    required this.onPickImage,
    required this.onPickFile,
    required this.onClearAttachment,
    required this.onPaste,
    required this.onContentInserted,
  });

  final TextEditingController controller;
  final bool isLoading;
  final bool enabled;
  final bool supportsAttachments;
  final RemoteCodingAttachmentDraft? attachment;
  final bool isAttachmentBusy;
  final RemoteCodingComposerSettings? composerSettings;
  final AssistantMode assistantMode;
  final List<SlashCommandDefinition> slashCommands;
  final SlashCommandHandler? onSlashCommand;
  final ValueChanged<AssistantMode> onAssistantModeSelected;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final ComposerModelListLoader onLoadModels;
  final ComposerModelSelectionChanged onComposerSettingsChanged;
  final VoidCallback onPickImage;
  final VoidCallback onPickFile;
  final VoidCallback onClearAttachment;
  final VoidCallback onPaste;
  final Future<void> Function(KeyboardInsertedContent) onContentInserted;

  List<SlashCommandDefinition> _suggestions() {
    if (slashCommands.isEmpty || onSlashCommand == null || attachment != null) {
      return const <SlashCommandDefinition>[];
    }
    return filterSlashCommandSuggestions(controller.text, slashCommands);
  }

  void _showSlashCommandFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _applySlashSuggestion(
    BuildContext context,
    SlashCommandDefinition command,
  ) {
    final nextText = '/${command.name} ';
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    if (command.requiresArguments) return;
    unawaited(_submitSlashCommand(context));
  }

  Future<bool> _submitSlashCommand(BuildContext context) async {
    if (onSlashCommand == null || attachment != null) return false;
    final rawInput = controller.text.trimRight();
    final parsed = parseSlashCommandInput(rawInput);
    if (parsed == null) return false;
    final definition = findSlashCommand(parsed.commandName, slashCommands);
    if (definition == null) {
      _showSlashCommandFeedback(
        context,
        'message.slash_unknown_command'.tr(
          namedArgs: {'command': parsed.commandName},
        ),
      );
      controller.clear();
      return true;
    }
    if (definition.requiresArguments && parsed.args.isEmpty) {
      _showSlashCommandFeedback(
        context,
        'message.slash_missing_arguments'.tr(
          namedArgs: {'command': definition.name, 'usage': definition.usage},
        ),
      );
      return true;
    }
    if (!definition.acceptsArguments && parsed.args.isNotEmpty) {
      _showSlashCommandFeedback(
        context,
        'message.slash_unexpected_arguments'.tr(
          namedArgs: {'command': definition.name},
        ),
      );
      return true;
    }

    final result = await onSlashCommand!(
      SlashCommandInvocation(
        definition: definition,
        rawInput: rawInput,
        commandName: parsed.commandName,
        args: parsed.args,
      ),
    );
    if (!context.mounted) return true;
    if (result.feedbackMessage != null) {
      _showSlashCommandFeedback(context, result.feedbackMessage!);
    }
    final prompt = result.promptToSend;
    if (prompt != null && prompt.trim().isNotEmpty) {
      controller.value = TextEditingValue(
        text: prompt,
        selection: TextSelection.collapsed(offset: prompt.length),
      );
      onSend();
    } else if (result.clearInput) {
      controller.clear();
    }
    return true;
  }

  void _handleSend(BuildContext context) {
    if (attachment == null && onSlashCommand != null) {
      final parsed = parseSlashCommandInput(controller.text.trimRight());
      if (parsed != null) {
        unawaited(_submitSlashCommand(context));
        return;
      }
    }
    onSend();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrowComposer = MediaQuery.sizeOf(context).width < 480;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RemoteAttachmentPreview(
                  attachment: attachment!,
                  onClear: onClearAttachment,
                ),
              ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, _, _) {
                final suggestions = _suggestions();
                if (suggestions.isEmpty) return const SizedBox.shrink();
                return MessageInputSlashSuggestionList(
                  suggestions: suggestions,
                  selectedIndex: 0,
                  onSelected: (index) =>
                      _applySlashSuggestion(context, suggestions[index]),
                );
              },
            ),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(context.radii.lg),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        if (supportsAttachments)
                          PasteTextIntent: CallbackAction<PasteTextIntent>(
                            onInvoke: (_) {
                              onPaste();
                              return null;
                            },
                          ),
                      },
                      child: TextField(
                        controller: controller,
                        enabled: enabled,
                        contentInsertionConfiguration: supportsAttachments
                            ? ContentInsertionConfiguration(
                                onContentInserted: (content) {
                                  unawaited(onContentInserted(content));
                                },
                                allowedMimeTypes: const [
                                  'image/png',
                                  'image/jpeg',
                                  'image/gif',
                                  'image/webp',
                                  'image/heic',
                                  'image/heif',
                                  'image/tiff',
                                  'image/bmp',
                                ],
                              )
                            : null,
                        contextMenuBuilder: (context, editableTextState) {
                          if (!supportsAttachments) {
                            return AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: editableTextState.contextMenuAnchors,
                              buttonItems:
                                  editableTextState.contextMenuButtonItems,
                            );
                          }
                          final buttonItems = editableTextState
                              .contextMenuButtonItems
                              .map((item) {
                                if (item.type != ContextMenuButtonType.paste) {
                                  return item;
                                }
                                return ContextMenuButtonItem(
                                  onPressed: () {
                                    editableTextState.hideToolbar();
                                    onPaste();
                                  },
                                  type: ContextMenuButtonType.paste,
                                  label: item.label,
                                );
                              })
                              .toList();
                          if (!buttonItems.any(
                            (item) => item.type == ContextMenuButtonType.paste,
                          )) {
                            buttonItems.add(
                              ContextMenuButtonItem(
                                onPressed: () {
                                  editableTextState.hideToolbar();
                                  onPaste();
                                },
                                type: ContextMenuButtonType.paste,
                              ),
                            );
                          }
                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: editableTextState.contextMenuAnchors,
                            buttonItems: buttonItems,
                          );
                        },
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'message.input_hint'.tr(),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasContent =
                          value.text.trim().isNotEmpty || attachment != null;
                      final canSend =
                          enabled && !isAttachmentBusy && hasContent;
                      return Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (supportsAttachments)
                                    IgnorePointer(
                                      ignoring: isAttachmentBusy,
                                      child: Opacity(
                                        opacity: isAttachmentBusy ? 0.55 : 1,
                                        child: ComposerAttachmentButton(
                                          onPickImage: onPickImage,
                                          onPickFile: onPickFile,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  ComposerModelSelector(
                                    enabled:
                                        enabled &&
                                        !isLoading &&
                                        !isAttachmentBusy,
                                    compact: isNarrowComposer,
                                    selection: composerSettings == null
                                        ? null
                                        : ComposerModelSelection(
                                            model: composerSettings!.model,
                                            reasoningEffort: composerSettings!
                                                .reasoningEffort,
                                            enableThinking: composerSettings!
                                                .enableThinking,
                                          ),
                                    modelLoader: onLoadModels,
                                    onSelectionChanged:
                                        onComposerSettingsChanged,
                                  ),
                                  const SizedBox(width: 4),
                                  _RemoteAssistantModeSelector(
                                    enabled:
                                        enabled &&
                                        !isLoading &&
                                        !isAttachmentBusy,
                                    assistantMode: assistantMode,
                                    onSelected: onAssistantModeSelected,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (hasContent) ...[
                            IconButton(
                              onPressed: canSend
                                  ? () => _handleSend(context)
                                  : null,
                              icon: isAttachmentBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              tooltip: 'message.send'.tr(),
                              style: IconButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                              ),
                            ),
                            if (isLoading) const SizedBox(width: 4),
                          ],
                          if (isLoading)
                            IconButton(
                              onPressed: enabled ? onCancel : null,
                              icon: const Icon(Icons.stop_circle),
                              tooltip: 'message.cancel'.tr(),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.errorContainer,
                                foregroundColor:
                                    theme.colorScheme.onErrorContainer,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteAttachmentPreview extends StatelessWidget {
  const _RemoteAttachmentPreview({
    required this.attachment,
    required this.onClear,
  });

  final RemoteCodingAttachmentDraft attachment;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = attachment.isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              attachment.bytes,
              height: 96,
              width: 96,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
            ),
          )
        : Expanded(
            child: Row(
              children: [
                Icon(Icons.attach_file, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${attachment.name} · ${formatAttachmentSize(attachment.bytes.length)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          preview,
          const Spacer(),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close),
            tooltip: 'Remove attachment',
          ),
        ],
      ),
    );
  }
}
