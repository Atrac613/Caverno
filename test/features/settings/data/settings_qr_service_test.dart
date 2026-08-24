import 'dart:convert';
import 'dart:io';

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

    test('rejects oversized Base64 text before decoding', () {
      final bounded = SettingsQrService(
        maxCompressedBytes: 3,
        maxDecompressedBytes: 128,
      );

      expect(
        () => bounded.parseQrString('AAAAA'),
        throwsA(
          isA<SettingsQrLimitException>().having(
            (error) => error.message,
            'message',
            contains('Base64 text exceeded 4 characters'),
          ),
        ),
      );
    });

    test('rejects decoded compressed input before decompression', () {
      final bounded = SettingsQrService(
        maxCompressedBytes: 4,
        maxDecompressedBytes: 128,
      );
      final encoded = base64Encode(List<int>.filled(5, 0));

      expect(
        () => bounded.parseQrString(encoded),
        throwsA(
          isA<SettingsQrLimitException>().having(
            (error) => error.message,
            'message',
            contains('compressed payload exceeded 4 bytes'),
          ),
        ),
      );
    });

    test('rejects gzip expansion while decompression is in progress', () {
      final compressed = GZipCodec().encode(List<int>.filled(129, 0x61));
      final bounded = SettingsQrService(
        maxCompressedBytes: compressed.length,
        maxDecompressedBytes: 128,
      );

      expect(
        () => bounded.parseQrString(base64Encode(compressed)),
        throwsA(
          isA<SettingsQrLimitException>().having(
            (error) => error.message,
            'message',
            contains('decompressed payload exceeded 128 bytes'),
          ),
        ),
      );
    });

    test('accepts valid settings exactly at both byte ceilings', () {
      final settings = AppSettings.defaults();
      final encoded = service.generateQrString(settings);
      final compressed = base64Decode(encoded);
      final decompressed = GZipCodec().decode(compressed);
      final bounded = SettingsQrService(
        maxCompressedBytes: compressed.length,
        maxDecompressedBytes: decompressed.length,
      );

      final parsed = bounded.parseQrString(encoded);
      expect(parsed.model, settings.model);
      expect(parsed.baseUrl, settings.baseUrl);
      expect(parsed.apiKey, isEmpty);
      expect(bounded.generateQrString(settings), encoded);
    });

    test('refuses to generate output outside the import contract', () {
      final bounded = SettingsQrService(
        maxCompressedBytes: 256,
        maxDecompressedBytes: 1,
      );

      expect(
        () => bounded.generateQrString(AppSettings.defaults()),
        throwsA(isA<SettingsQrLimitException>()),
      );
    });

    test('rejects non-positive limits', () {
      expect(
        () => SettingsQrService(maxCompressedBytes: 0, maxDecompressedBytes: 1),
        throwsArgumentError,
      );
      expect(
        () => SettingsQrService(maxCompressedBytes: 1, maxDecompressedBytes: 0),
        throwsArgumentError,
      );
    });
  });
}
