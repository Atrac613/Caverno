// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// Transport type for an MCP server.
enum McpServerType { http, stdio }

enum McpServerTrustState { pending, trusted, blocked }

@freezed
abstract class McpServerConfig with _$McpServerConfig {
  const McpServerConfig._();

  const factory McpServerConfig({
    @Default('') String url,
    @Default(true) bool enabled,
    @JsonKey(unknownEnumValue: McpServerType.http)
    @Default(McpServerType.http)
    McpServerType type,
    @JsonKey(unknownEnumValue: McpServerTrustState.trusted)
    @Default(McpServerTrustState.trusted)
    McpServerTrustState trustState,
    @Default('') String command,
    @Default(<String>[]) List<String> args,
    DateTime? trustedAt,
  }) = _McpServerConfig;

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      _$McpServerConfigFromJson(json);

  String get normalizedUrl => url.trim();

  /// Whether this server configuration has enough data to attempt a connection.
  bool get isValid => switch (type) {
    McpServerType.http => normalizedUrl.isNotEmpty,
    McpServerType.stdio => command.trim().isNotEmpty,
  };

  /// Human-readable label for display and logging.
  String get displayLabel => switch (type) {
    McpServerType.http => normalizedUrl,
    McpServerType.stdio =>
      args.isEmpty ? command.trim() : '${command.trim()} ${args.join(' ')}',
  };

  String get trustSourceLabel => switch (type) {
    McpServerType.http => 'Remote MCP endpoint',
    McpServerType.stdio => 'Local stdio command',
  };

  String get trustIdentity => switch (type) {
    McpServerType.http => 'http:${normalizedUrl.toLowerCase()}',
    McpServerType.stdio =>
      'stdio:${command.trim().toLowerCase()}::${args.join('\u{1f}')}',
  };

  bool get isTrusted => trustState == McpServerTrustState.trusted;

  bool get isBlocked => trustState == McpServerTrustState.blocked;

  bool get needsTrustReview => trustState == McpServerTrustState.pending;

  bool get exposesToolsToModel => enabled && isValid && isTrusted;
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
    @Default('') String googleChatWebhookUrl,
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
    @Default(true) bool confirmFileMutations,
    @Default(true) bool confirmLocalCommands,
    @Default(true) bool confirmGitWrites,
    @Default(false) bool showMemoryUpdates,
    @Default(false) bool demoMode,
    @Default(<String>[]) List<String> disabledBuiltInTools,
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

  String get normalizedGoogleChatWebhookUrl => googleChatWebhookUrl.trim();

  bool get hasGoogleChatWebhook => normalizedGoogleChatWebhookUrl.isNotEmpty;

  Set<String> get disabledBuiltInToolsSet =>
      Set<String>.from(disabledBuiltInTools);

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
    final seenIds = <String>{};

    for (final server in effectiveMcpServers) {
      if (!server.enabled || !server.isValid || !server.isTrusted) continue;
      final id = server.displayLabel;
      if (!seenIds.add(id)) continue;

      enabledServers.add(
        server.type == McpServerType.http
            ? server.copyWith(url: server.normalizedUrl)
            : server,
      );
    }

    return enabledServers;
  }

  List<McpServerConfig> get connectableMcpServers {
    final connectableServers = <McpServerConfig>[];
    final seenIds = <String>{};

    for (final server in effectiveMcpServers) {
      if (!server.enabled || !server.isValid || server.isBlocked) continue;
      final id = server.displayLabel;
      if (!seenIds.add(id)) continue;
      connectableServers.add(
        server.type == McpServerType.http
            ? server.copyWith(url: server.normalizedUrl)
            : server,
      );
    }

    return connectableServers;
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
      if (!value.isTrusted) {
        continue;
      }
      normalized.add(trimmed);
    }

    return normalized;
  }
}
