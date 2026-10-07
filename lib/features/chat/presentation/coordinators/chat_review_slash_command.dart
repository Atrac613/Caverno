import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/coding_project.dart';
import '../providers/chat_notifier.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_prompt_template.dart';

/// Validates and starts the explicit read-only review slash command.
abstract final class ChatReviewSlashCommand {
  static SlashCommandExecutionResult handle({
    required WidgetRef ref,
    required SlashCommandInvocation invocation,
    required String languageCode,
    required bool isCodingWorkspace,
    required CodingProject? activeProject,
  }) {
    final settings = ref.read(settingsNotifierProvider);
    if (!isCodingWorkspace || activeProject == null) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_review_unavailable'.tr(),
      );
    }
    if (!settings.hasCodeReviewRoute) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: 'chat.slash_review_not_configured'.tr(),
      );
    }
    final template = builtInSlashCommandPromptTemplates.firstWhere(
      (template) => template.id == 'review',
    );
    unawaited(
      ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            template.expand(
              args: invocation.args,
              commandName: invocation.commandName,
            ),
            languageCode: languageCode,
            purpose: PrimaryTurnPurpose.codeReview,
            bypassPlanMode: true,
          ),
    );
    return SlashCommandExecutionResult.handled;
  }
}
