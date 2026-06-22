import 'dart:async';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/conversation_participant.dart';
import '../../domain/entities/message.dart';
import 'chat_datasource.dart';
import 'mesh_secondary_completion_runner.dart';

class ParticipantCompletionRequest {
  const ParticipantCompletionRequest({
    required this.participant,
    required this.messages,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  final ConversationParticipant participant;
  final List<Message> messages;
  final String model;
  final double temperature;
  final int maxTokens;
}

class ParticipantCompletionRunner {
  const ParticipantCompletionRunner({required this.meshRunner});

  final MeshSecondaryCompletionRunner<ChatDataSource> meshRunner;

  Future<void> stream({
    required ChatDataSource primary,
    required AppSettings settings,
    required ParticipantCompletionRequest request,
    required bool Function() shouldContinue,
    required FutureOr<void> Function(String chunk) onChunk,
  }) {
    final endpointId = settings.llmProvider == LlmProvider.openAiCompatible
        ? request.participant.endpointId
        : '';
    return meshRunner.run<void>(
      primary: primary,
      primaryBaseUrl: settings.baseUrl,
      primaryApiKey: settings.apiKey,
      endpoints: settings.namedEndpoints,
      endpointId: endpointId,
      model: request.model,
      fallbackModel: settings.effectiveModel,
      call: (dataSource, resolvedModel) async {
        final stream = dataSource.streamChatCompletion(
          messages: request.messages,
          model: resolvedModel,
          temperature: request.temperature,
          maxTokens: request.maxTokens,
        );
        await for (final chunk in stream) {
          if (!shouldContinue()) {
            return;
          }
          await onChunk(chunk);
        }
      },
    );
  }
}
