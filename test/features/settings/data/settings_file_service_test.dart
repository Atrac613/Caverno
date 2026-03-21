import 'dart:convert';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/settings/data/settings_file_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppSettings validSettings;

  setUp(() {
    validSettings = const AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'test-model',
      apiKey: 'test-key',
      temperature: 0.7,
      maxTokens: 4096,
      mcpUrl: 'http://localhost:8081',
      whisperUrl: 'http://localhost:8080',
      voicevoxUrl: 'http://localhost:50021',
    );
  });

  group('validateSettings', () {
    test('accepts valid settings', () {
      expect(
        () => SettingsFileService.validateSettings(validSettings),
        returnsNormally,
      );
    });

    test('accepts settings with empty optional URLs', () {
      final settings = validSettings.copyWith(
        mcpUrl: '',
        whisperUrl: '',
        voicevoxUrl: '',
      );
      expect(
        () => SettingsFileService.validateSettings(settings),
        returnsNormally,
      );
    });

    test('accepts settings with https URLs', () {
      final settings = validSettings.copyWith(
        baseUrl: 'https://api.example.com/v1',
        mcpUrl: 'https://mcp.example.com',
      );
      expect(
        () => SettingsFileService.validateSettings(settings),
        returnsNormally,
      );
    });

    test('rejects empty baseUrl', () {
      final settings = validSettings.copyWith(baseUrl: '');
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('baseUrl'),
          ),
        ),
      );
    });

    test('rejects invalid baseUrl scheme', () {
      final settings = validSettings.copyWith(baseUrl: 'ftp://example.com');
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty model', () {
      final settings = validSettings.copyWith(model: '');
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('model'),
          ),
        ),
      );
    });

    test('rejects empty apiKey', () {
      final settings = validSettings.copyWith(apiKey: '');
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('apiKey'),
          ),
        ),
      );
    });

    test('rejects negative temperature', () {
      final settings = validSettings.copyWith(temperature: -0.1);
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('temperature'),
          ),
        ),
      );
    });

    test('rejects temperature above 2.0', () {
      final settings = validSettings.copyWith(temperature: 2.1);
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts boundary temperature values', () {
      expect(
        () => SettingsFileService.validateSettings(
          validSettings.copyWith(temperature: 0.0),
        ),
        returnsNormally,
      );
      expect(
        () => SettingsFileService.validateSettings(
          validSettings.copyWith(temperature: 2.0),
        ),
        returnsNormally,
      );
    });

    test('rejects zero maxTokens', () {
      final settings = validSettings.copyWith(maxTokens: 0);
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('maxTokens'),
          ),
        ),
      );
    });

    test('rejects maxTokens above 1,000,000', () {
      final settings = validSettings.copyWith(maxTokens: 1000001);
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects speechRate below 0.1', () {
      final settings = validSettings.copyWith(speechRate: 0.05);
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('speechRate'),
          ),
        ),
      );
    });

    test('rejects speechRate above 3.0', () {
      final settings = validSettings.copyWith(speechRate: 3.1);
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects negative voicevoxSpeakerId', () {
      final settings = validSettings.copyWith(voicevoxSpeakerId: -1);
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('voicevoxSpeakerId'),
          ),
        ),
      );
    });

    test('rejects invalid mcpUrl', () {
      final settings = validSettings.copyWith(mcpUrl: 'not-a-url');
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('mcpUrl'),
          ),
        ),
      );
    });

    test('rejects invalid whisperUrl', () {
      final settings = validSettings.copyWith(whisperUrl: 'invalid');
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('whisperUrl'),
          ),
        ),
      );
    });

    test('rejects invalid voicevoxUrl', () {
      final settings = validSettings.copyWith(voicevoxUrl: 'ws://wrong');
      expect(
        () => SettingsFileService.validateSettings(settings),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('voicevoxUrl'),
          ),
        ),
      );
    });
  });

  group('JSON round-trip', () {
    test('exported JSON can be deserialized and passes validation', () {
      final json = jsonEncode(validSettings.toJson());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final reimported = AppSettings.fromJson(decoded);

      expect(
        () => SettingsFileService.validateSettings(reimported),
        returnsNormally,
      );
      expect(reimported, equals(validSettings));
    });

    test('all fields survive round-trip', () {
      final settings = const AppSettings(
        baseUrl: 'https://api.example.com/v1',
        model: 'gpt-4',
        apiKey: 'sk-test-key',
        temperature: 1.5,
        maxTokens: 8192,
        mcpUrl: 'http://mcp.local:9090',
        mcpEnabled: true,
        ttsEnabled: false,
        autoReadEnabled: true,
        speechRate: 1.5,
        voiceModeAutoStop: false,
        whisperUrl: 'http://whisper.local:8080',
        voicevoxUrl: 'http://voicevox.local:50021',
        voicevoxSpeakerId: 3,
        language: 'ja',
        assistantMode: AssistantMode.coding,
      );

      final json = jsonDecode(jsonEncode(settings.toJson()))
          as Map<String, dynamic>;
      final restored = AppSettings.fromJson(json);

      expect(restored.baseUrl, settings.baseUrl);
      expect(restored.model, settings.model);
      expect(restored.apiKey, settings.apiKey);
      expect(restored.temperature, settings.temperature);
      expect(restored.maxTokens, settings.maxTokens);
      expect(restored.mcpUrl, settings.mcpUrl);
      expect(restored.mcpEnabled, settings.mcpEnabled);
      expect(restored.ttsEnabled, settings.ttsEnabled);
      expect(restored.autoReadEnabled, settings.autoReadEnabled);
      expect(restored.speechRate, settings.speechRate);
      expect(restored.voiceModeAutoStop, settings.voiceModeAutoStop);
      expect(restored.whisperUrl, settings.whisperUrl);
      expect(restored.voicevoxUrl, settings.voicevoxUrl);
      expect(restored.voicevoxSpeakerId, settings.voicevoxSpeakerId);
      expect(restored.language, settings.language);
      expect(restored.assistantMode, settings.assistantMode);
    });
  });
}
