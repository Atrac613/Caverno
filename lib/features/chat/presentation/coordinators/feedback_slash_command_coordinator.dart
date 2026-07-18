import '../../../settings/domain/entities/app_settings.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/services/feedback_submission_service.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_catalog.dart';

final class FeedbackSlashCommandCoordinator {
  const FeedbackSlashCommandCoordinator({
    required LlmSessionLogStore sessionLogStore,
    required FeedbackSubmissionClient feedbackSubmissionClient,
    required SlashCommandTextResolver text,
  }) : _sessionLogStore = sessionLogStore,
       _feedbackSubmissionClient = feedbackSubmissionClient,
       _text = text;

  final LlmSessionLogStore _sessionLogStore;
  final FeedbackSubmissionClient _feedbackSubmissionClient;
  final SlashCommandTextResolver _text;

  Future<SlashCommandExecutionResult> handle({
    required AppSettings settings,
    required Conversation? currentConversation,
    required String feedbackText,
  }) async {
    if (!settings.feedbackUploadEnabled) {
      return _keepInput('chat.slash_feedback_disabled');
    }
    if (!settings.isFeedbackUploadConfigured) {
      return _keepInput('chat.slash_feedback_not_configured');
    }
    if (currentConversation == null) {
      return _keepInput('chat.slash_feedback_no_session');
    }
    final loggingEnabled =
        LlmSessionLogStore.isEnabled(
          settingsEnabled: settings.enableLlmSessionLogs,
        ) &&
        !settings.demoMode;
    if (!loggingEnabled) {
      return _keepInput('chat.slash_feedback_requires_logs');
    }

    final context = LlmSessionLogContext(
      workspaceMode: currentConversation.workspaceMode,
      sessionId: currentConversation.id,
      sessionTitle: currentConversation.title,
      conversationId: currentConversation.id,
      phase: 'feedback',
    );
    final sessionLogFile = await _sessionLogStore.fileForContext(
      context,
      create: false,
    );

    try {
      final result = await _feedbackSubmissionClient.submit(
        FeedbackSubmissionInput(
          endpointUrl: settings.normalizedFeedbackEndpointUrl,
          authToken: settings.normalizedFeedbackEndpointAuthToken,
          feedbackText: feedbackText,
          sessionLogFile: sessionLogFile,
          context: context,
          conversationMessageCount: currentConversation.messages.length,
        ),
      );
      return SlashCommandExecutionResult(
        feedbackMessage: _text(
          'chat.slash_feedback_sent',
          namedArgs: {'key': result.objectKey},
        ),
      );
    } on FeedbackSubmissionException catch (error) {
      if (error.message == FeedbackSubmissionService.missingSessionLogMessage) {
        return _keepInput('chat.slash_feedback_no_session_log');
      }
      return _failed(error.message);
    } catch (error) {
      return _failed('$error');
    }
  }

  SlashCommandExecutionResult _keepInput(String key) {
    return SlashCommandExecutionResult.keepInput(feedbackMessage: _text(key));
  }

  SlashCommandExecutionResult _failed(String error) {
    return SlashCommandExecutionResult.keepInput(
      feedbackMessage: _text(
        'chat.slash_feedback_failed',
        namedArgs: {'error': error},
      ),
    );
  }
}
