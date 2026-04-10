// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

@freezed
abstract class McpServerConfig with _$McpServerConfig {
  const McpServerConfig._();

  const factory McpServerConfig({
    @Default('') String url,
    @Default(true) bool enabled,
  }) = _McpServerConfig;

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      _$McpServerConfigFromJson(json);

  String get normalizedUrl => url.trim();
}

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
    @Default(<McpServerConfig>[]) List<McpServerConfig> mcpServers,
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
    mcpServers: [McpServerConfig(url: 'http://localhost:8081', enabled: true)],
    mcpEnabled: true,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  List<McpServerConfig> get configuredMcpServers {
    if (mcpServers.isNotEmpty) {
      return List<McpServerConfig>.from(mcpServers);
    }

    return buildMcpServersFromUrls(mcpUrls.isNotEmpty ? mcpUrls : [mcpUrl]);
  }

  List<McpServerConfig> get effectiveMcpServers {
    return configuredMcpServers
        .map((server) => server.copyWith(url: server.normalizedUrl))
        .toList(growable: false);
  }

  List<McpServerConfig> get enabledMcpServers {
    final enabledServers = <McpServerConfig>[];
    final seenUrls = <String>{};

    for (final server in effectiveMcpServers) {
      final url = server.normalizedUrl;
      if (!server.enabled || url.isEmpty || !seenUrls.add(url)) {
        continue;
      }
      enabledServers.add(server.copyWith(url: url));
    }

    return enabledServers;
  }

  List<String> get effectiveMcpUrls {
    return enabledMcpServers
        .map((server) => server.normalizedUrl)
        .toList(growable: false);
  }

  String get primaryMcpUrl =>
      effectiveMcpUrls.isEmpty ? '' : effectiveMcpUrls.first;

  static List<String> normalizeMcpUrls(Iterable<String> values) {
    return activeMcpUrlsFromServers(buildMcpServersFromUrls(values));
  }

  static List<McpServerConfig> buildMcpServersFromUrls(
    Iterable<String> values,
  ) {
    return values
        .map((value) => McpServerConfig(url: value, enabled: true))
        .toList(growable: false);
  }

  static List<String> activeMcpUrlsFromServers(
    Iterable<McpServerConfig> values,
  ) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final value in values) {
      final trimmed = value.normalizedUrl;
      if (!value.enabled || trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }

    return normalized;
  }
}
