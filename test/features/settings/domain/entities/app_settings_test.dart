import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test('only trusted MCP servers are exposed to the model', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      mcpEnabled: true,
      mcpServers: [
        McpServerConfig(
          url: 'http://trusted.example',
          enabled: true,
          trustState: McpServerTrustState.trusted,
        ),
        McpServerConfig(
          url: 'http://pending.example',
          enabled: true,
          trustState: McpServerTrustState.pending,
        ),
        McpServerConfig(
          url: 'http://blocked.example',
          enabled: true,
          trustState: McpServerTrustState.blocked,
        ),
      ],
    );

    expect(
      settings.enabledMcpServers.map((server) => server.normalizedUrl),
      ['http://trusted.example'],
    );
    expect(
      settings.connectableMcpServers.map((server) => server.normalizedUrl),
      containsAll(['http://trusted.example', 'http://pending.example']),
    );
    expect(
      settings.connectableMcpServers.map((server) => server.normalizedUrl),
      isNot(contains('http://blocked.example')),
    );
  });

  test('normalizes the Google Chat webhook URL for delivery checks', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      googleChatWebhookUrl: ' https://chat.googleapis.com/v1/spaces/test ',
    );

    expect(
      settings.normalizedGoogleChatWebhookUrl,
      'https://chat.googleapis.com/v1/spaces/test',
    );
    expect(settings.hasGoogleChatWebhook, isTrue);
  });
}
