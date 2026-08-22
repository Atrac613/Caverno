import 'package:caverno/features/settings/data/settings_qr_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsQrService', () {
    final service = SettingsQrService();

    test('encodes import-compatible settings without credentials', () {
      final settings = AppSettings.defaults().copyWith(
        baseUrl: 'https://example.com/api',
        model: 'test-model',
        apiKey: 'test-key',
        llmEndpoints: const [
          LlmEndpoint(
            id: 'secondary',
            baseUrl: 'https://secondary.example.com/v1',
            apiKey: 'secondary-key',
          ),
        ],
        googleChatWebhookUrl:
            'https://chat.googleapis.com/v1/spaces/webhook-secret',
        feedbackEndpointAuthToken: 'feedback-token',
        mcpServers: const [
          McpServerConfig(
            url: 'https://mcp.example.com',
            env: {'MCP_TOKEN': 'mcp-token'},
          ),
        ],
        temperature: 1.5,
        maxTokens: 2048,
        showMemoryUpdates: true,
      );

      final qrString = service.generateQrString(settings);
      expect(qrString, isNotEmpty);

      final decodedSettings = service.parseQrString(qrString);
      expect(decodedSettings.apiKey, isEmpty);
      expect(decodedSettings.llmEndpoints.single.apiKey, isEmpty);
      expect(decodedSettings.googleChatWebhookUrl, isEmpty);
      expect(decodedSettings.feedbackEndpointAuthToken, isEmpty);
      expect(decodedSettings.mcpServers.single.env, isEmpty);
      expect(decodedSettings.baseUrl, settings.baseUrl);
      expect(decodedSettings.model, settings.model);
      expect(decodedSettings.temperature, settings.temperature);
      expect(decodedSettings.showMemoryUpdates, isTrue);
    });

    test('should throw FormatException for invalid data', () {
      expect(
        () => service.parseQrString('invalid-base64'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
