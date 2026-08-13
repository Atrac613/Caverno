import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/conversation.dart';
import '../providers/chat_notifier.dart';
import '../providers/conversations_notifier.dart';
import '../providers/pro_reasoning_run_notifier.dart';
import '../slash_commands/slash_command.dart';
import '../widgets/slash_command_help_sheet.dart';
import 'composer_assistant_mode_coordinator.dart';

final class ChatPageComposerRuntimeCoordinator {
  const ChatPageComposerRuntimeCoordinator({
    required this.ref,
    required this.leaveDashboard,
  });

  final WidgetRef ref;
  final VoidCallback leaveDashboard;

  bool startProReasoning(BuildContext context, String question) {
    final proState = ref.read(proReasoningRunProvider);
    final chatState = ref.read(chatNotifierProvider);
    final conversationsState = ref.read(conversationsNotifierProvider);
    if (proState.isRunning ||
        chatState.isLoading ||
        conversationsState.activeWorkspaceMode != WorkspaceMode.chat) {
      return false;
    }

    leaveDashboard();
    final settings = ref.read(settingsNotifierProvider);
    unawaited(
      ref
          .read(proReasoningRunProvider.notifier)
          .start(
            question,
            depth: settings.proReasoningDepth,
            languageCode: context.mounted ? context.locale.languageCode : 'en',
          )
          .then((started) {
            if (started || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('message.pro_reasoning_failed'.tr())),
            );
          }),
    );
    return true;
  }

  void cancelActiveResponse() {
    if (ref.read(proReasoningRunProvider).isRunning) {
      ref.read(proReasoningRunProvider.notifier).cancel();
      return;
    }
    ref.read(chatNotifierProvider.notifier).cancelStreaming();
  }

  Future<void> selectAssistantMode(
    AssistantMode mode, {
    required bool isCodingWorkspace,
    required Conversation? currentConversation,
  }) {
    return ComposerAssistantModeCoordinator(
      conversationsNotifier: ref.read(conversationsNotifierProvider.notifier),
      updateAssistantMode: ref
          .read(settingsNotifierProvider.notifier)
          .updateAssistantMode,
      dismissPlanProposal: ref
          .read(chatNotifierProvider.notifier)
          .dismissPlanProposal,
    ).select(
      mode,
      isCodingWorkspace: isCodingWorkspace,
      hasConversation: currentConversation != null,
      isPlanningSession: currentConversation?.isPlanningSession ?? false,
    );
  }

  Future<void> showSlashCommandHelp(
    BuildContext context,
    List<SlashCommandDefinition> commands,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SlashCommandHelpSheet(
        title: 'chat.slash_commands_title'.tr(),
        commands: commands,
      ),
    );
  }
}
