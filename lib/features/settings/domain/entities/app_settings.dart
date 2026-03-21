// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    required String baseUrl,
    required String model,
    required String apiKey,
    required double temperature,
    required int maxTokens,
    @Default('') String mcpUrl,
    @Default(false) bool mcpEnabled,
    // Voice settings
    @Default(true) bool ttsEnabled,
    @Default(false) bool autoReadEnabled,
    @Default(1.0) double speechRate,
    // Voice mode (Whisper + VOICEVOX)
    @Default('http://localhost:8080') String whisperUrl,
    @Default('http://localhost:50021') String voicevoxUrl,
    @Default(0) int voicevoxSpeakerId,
    @JsonKey(unknownEnumValue: AssistantMode.general)
    @Default(AssistantMode.general)
    AssistantMode assistantMode,
  }) = _AppSettings;

  factory AppSettings.defaults() => const AppSettings(
    baseUrl: ApiConstants.defaultBaseUrl,
    model: ApiConstants.defaultModel,
    apiKey: ApiConstants.defaultApiKey,
    temperature: ApiConstants.defaultTemperature,
    maxTokens: ApiConstants.defaultMaxTokens,
    mcpUrl: 'http://localhost:8081',
    mcpEnabled: true,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}
