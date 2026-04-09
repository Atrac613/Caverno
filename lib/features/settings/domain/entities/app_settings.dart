// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

@freezed
abstract class AppSettings with _$AppSettings {
  const AppSettings._();

  const factory AppSettings({
    required String baseUrl,
    required String model,
    required String apiKey,
    required double temperature,
    required int maxTokens,
    @Default('') String mcpUrl,
    @Default(<String>[]) List<String> mcpUrls,
    @Default(false) bool mcpEnabled,
    // Voice settings
    @Default(true) bool ttsEnabled,
    @Default(false) bool autoReadEnabled,
    @Default(0.5) double speechRate,
    // Voice mode (Whisper + VOICEVOX)
    @Default(true) bool voiceModeAutoStop,
    @Default('http://localhost:8080') String whisperUrl,
    @Default('http://localhost:50021') String voicevoxUrl,
    @Default(0) int voicevoxSpeakerId,
    @Default('system') String language,
    @JsonKey(unknownEnumValue: AssistantMode.general)
    @Default(AssistantMode.general)
    AssistantMode assistantMode,
    @Default(false) bool demoMode,
  }) = _AppSettings;

  factory AppSettings.defaults() => const AppSettings(
    baseUrl: ApiConstants.defaultBaseUrl,
    model: ApiConstants.defaultModel,
    apiKey: ApiConstants.defaultApiKey,
    temperature: ApiConstants.defaultTemperature,
    maxTokens: ApiConstants.defaultMaxTokens,
    mcpUrl: 'http://localhost:8081',
    mcpUrls: ['http://localhost:8081'],
    mcpEnabled: true,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  List<String> get effectiveMcpUrls {
    final configuredUrls = mcpUrls.isNotEmpty ? mcpUrls : [mcpUrl];
    return normalizeMcpUrls(configuredUrls);
  }

  String get primaryMcpUrl =>
      effectiveMcpUrls.isEmpty ? '' : effectiveMcpUrls.first;

  static List<String> normalizeMcpUrls(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }

    return normalized;
  }
}
