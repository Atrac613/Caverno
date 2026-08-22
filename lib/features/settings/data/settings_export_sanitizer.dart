import '../domain/entities/app_settings.dart';

/// Builds an import-compatible settings payload without credential material.
final class SettingsExportSanitizer {
  const SettingsExportSanitizer();

  Map<String, dynamic> toExportJson(AppSettings settings) {
    final sanitized = settings.copyWith(
      apiKey: '',
      llmEndpoints: [
        for (final endpoint in settings.llmEndpoints)
          endpoint.copyWith(apiKey: ''),
      ],
      googleChatWebhookUrl: '',
      feedbackEndpointAuthToken: '',
      mcpServers: [
        for (final server in settings.mcpServers)
          server.copyWith(env: const <String, String>{}),
      ],
      externalToolHooks: [
        for (final hook in settings.externalToolHooks)
          hook.copyWith(env: const <String, String>{}),
      ],
    );
    return sanitized.toJson();
  }
}
