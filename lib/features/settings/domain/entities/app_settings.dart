// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// Transport type for an MCP server.
enum McpServerType { http, stdio }

enum McpServerTrustState { pending, trusted, blocked }

enum LocalCommandPermissionAction { allow, deny, ask }

enum LocalCommandPermissionMatch { exact, prefix }

/// Approval policy levels shared by the coding agent
/// ([AppSettings.codingApprovalMode]) and chat-mode built-in browser
/// automation ([AppSettings.chatApprovalMode]).
///
/// - [defaultPermissions]: prompt the user before each high-risk action.
/// - [autoReview]: let the configured LLM endpoint allow/deny each action.
/// - [fullAccess]: run high-risk actions without an approval prompt.
enum ToolApprovalMode { defaultPermissions, autoReview, fullAccess }

enum CodingVerificationTriggerPolicy { onCompletionClaim, onRequestOnly, off }

enum ReasoningEffortPreference { automatic, low, medium, high }

extension ReasoningEffortPreferenceApi on ReasoningEffortPreference {
  String? get apiValue => switch (this) {
    ReasoningEffortPreference.automatic => null,
    ReasoningEffortPreference.low => 'low',
    ReasoningEffortPreference.medium => 'medium',
    ReasoningEffortPreference.high => 'high',
  };
}

@freezed
abstract class LocalCommandPermissionRule with _$LocalCommandPermissionRule {
  const LocalCommandPermissionRule._();

  const factory LocalCommandPermissionRule({
    required String id,
    @Default(true) bool enabled,
    @JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask)
    @Default(LocalCommandPermissionAction.ask)
    LocalCommandPermissionAction action,
    @JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact)
    @Default(LocalCommandPermissionMatch.exact)
    LocalCommandPermissionMatch match,
    @Default('') String pattern,
    @Default('') String workingDirectory,
    DateTime? createdAt,
  }) = _LocalCommandPermissionRule;

  factory LocalCommandPermissionRule.fromJson(Map<String, dynamic> json) =>
      _$LocalCommandPermissionRuleFromJson(json);

  String get normalizedPattern => pattern.trim();

  String get normalizedWorkingDirectory => workingDirectory.trim();

  bool get isUsable => enabled && normalizedPattern.isNotEmpty;
}

@freezed
abstract class RoutineComputerUseActionAllowlistEntry
    with _$RoutineComputerUseActionAllowlistEntry {
  const RoutineComputerUseActionAllowlistEntry._();

  const factory RoutineComputerUseActionAllowlistEntry({
    required String id,
    @Default(true) bool enabled,
    @Default('') String label,
    @Default('') String toolName,
    @Default('') String targetLabelContains,
    @Default('') String targetRole,
    @Default('') String targetAction,
    @Default('') String targetRisk,
    @Default('') String appNameContains,
    @Default('') String appBundleId,
    @Default('') String windowTitleContains,
    @Default('') String urlHost,
    @Default('') String urlStartsWith,
    @Default('') String exactText,
  }) = _RoutineComputerUseActionAllowlistEntry;

  factory RoutineComputerUseActionAllowlistEntry.fromJson(
    Map<String, dynamic> json,
  ) => _$RoutineComputerUseActionAllowlistEntryFromJson(json);

  String get normalizedToolName => toolName.trim();

  String get normalizedLabel => label.trim();

  bool get hasBoundary {
    return targetLabelContains.trim().isNotEmpty ||
        targetRole.trim().isNotEmpty ||
        targetAction.trim().isNotEmpty ||
        targetRisk.trim().isNotEmpty ||
        appNameContains.trim().isNotEmpty ||
        appBundleId.trim().isNotEmpty ||
        windowTitleContains.trim().isNotEmpty ||
        urlHost.trim().isNotEmpty ||
        urlStartsWith.trim().isNotEmpty ||
        exactText.isNotEmpty;
  }
}

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
    @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)
    @Default(ReasoningEffortPreference.automatic)
    ReasoningEffortPreference reasoningEffort,
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
    @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)
    @Default(ToolApprovalMode.defaultPermissions)
    ToolApprovalMode codingApprovalMode,
    // Approval policy for chat-mode built-in browser automation. Reuses the
    // shared [ToolApprovalMode] levels but is independent from coding writes.
    @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)
    @Default(ToolApprovalMode.defaultPermissions)
    ToolApprovalMode chatApprovalMode,
    @Default(true) bool confirmFileMutations,
    @Default(true) bool confirmLocalCommands,
    @Default(true) bool confirmGitWrites,
    @Default(true) bool enableCodingVerificationFeedback,
    @JsonKey(
      unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim,
    )
    @Default(CodingVerificationTriggerPolicy.onCompletionClaim)
    CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,
    @Default(90) int codingVerificationTimeoutSeconds,
    @Default(5) int codingVerificationMaxFailures,
    @Default(true) bool enableAgentsMd,
    @Default(false) bool showMemoryUpdates,
    @Default(false) bool enableLlmSessionLogs,
    @Default(false) bool demoMode,
    @Default(false) bool onboardingCompleted,
    @Default(false) bool browserToolsEnabled,
    @Default(<String>[]) List<String> disabledBuiltInTools,
    @Default(<LocalCommandPermissionRule>[])
    List<LocalCommandPermissionRule> localCommandPermissionRules,
    @Default(<RoutineComputerUseActionAllowlistEntry>[])
    List<RoutineComputerUseActionAllowlistEntry>
    routineComputerUseActionAllowlist,
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
      _$AppSettingsFromJson(migrateLegacyJson(json));

  static const int minCodingVerificationTimeoutSeconds = 10;
  static const int maxCodingVerificationTimeoutSeconds = 300;
  static const int defaultCodingVerificationTimeoutSeconds = 90;
  static const int minCodingVerificationMaxFailures = 1;
  static const int maxCodingVerificationMaxFailures = 20;
  static const int defaultCodingVerificationMaxFailures = 5;

  static Map<String, dynamic> migrateLegacyJson(Map<String, dynamic> json) {
    if (json.containsKey('codingApprovalMode')) {
      return json;
    }

    final migrated = Map<String, dynamic>.from(json);
    final confirmFileMutations =
        migrated['confirmFileMutations'] as bool? ?? true;
    final confirmLocalCommands =
        migrated['confirmLocalCommands'] as bool? ?? true;
    final confirmGitWrites = migrated['confirmGitWrites'] as bool? ?? true;
    migrated['codingApprovalMode'] =
        !confirmFileMutations && !confirmLocalCommands && !confirmGitWrites
        ? 'fullAccess'
        : 'defaultPermissions';
    return migrated;
  }

  String get normalizedGoogleChatWebhookUrl => googleChatWebhookUrl.trim();

  bool get hasGoogleChatWebhook => normalizedGoogleChatWebhookUrl.isNotEmpty;

  int get effectiveCodingVerificationTimeoutSeconds =>
      codingVerificationTimeoutSeconds
          .clamp(
            minCodingVerificationTimeoutSeconds,
            maxCodingVerificationTimeoutSeconds,
          )
          .toInt();

  int get effectiveCodingVerificationMaxFailures =>
      codingVerificationMaxFailures
          .clamp(
            minCodingVerificationMaxFailures,
            maxCodingVerificationMaxFailures,
          )
          .toInt();

  bool get runsCodingVerificationOnCompletionClaim {
    return enableCodingVerificationFeedback &&
        codingVerificationTriggerPolicy ==
            CodingVerificationTriggerPolicy.onCompletionClaim;
  }

  Set<String> get disabledBuiltInToolsSet =>
      Set<String>.from(disabledBuiltInTools);

  /// Whether any chat-mode high-risk tool governed by the shared approval gate
  /// is currently exposed. Drives whether the chat permission-mode selector is
  /// shown. Browser tools have their own enable flag; SSH / BLE / serial are on
  /// unless explicitly disabled.
  bool get exposesGatedChatTools {
    if (browserToolsEnabled) return true;
    const connectionTools = {'ssh_connect', 'ble_connect', 'serial_open'};
    final disabled = disabledBuiltInToolsSet;
    return connectionTools.any((tool) => !disabled.contains(tool));
  }

  List<LocalCommandPermissionRule> get enabledLocalCommandPermissionRules =>
      localCommandPermissionRules
          .where((rule) => rule.enabled && rule.normalizedPattern.isNotEmpty)
          .toList(growable: false);

  List<RoutineComputerUseActionAllowlistEntry>
  get enabledRoutineComputerUseActionAllowlist =>
      routineComputerUseActionAllowlist
          .where(
            (entry) =>
                entry.enabled &&
                entry.normalizedToolName.isNotEmpty &&
                entry.hasBoundary,
          )
          .toList(growable: false);

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
