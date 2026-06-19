import 'dart:convert';
import 'dart:io';

import '../../../core/types/assistant_mode.dart';
import '../../../core/utils/logger.dart';
import '../domain/entities/app_settings.dart';

class ExternalSettingsSnapshot {
  const ExternalSettingsSnapshot({
    this.overrides = const ExternalSettingsOverrides(),
    this.mcpServers = const <McpServerConfig>[],
    this.hooks = const <ExternalToolHook>[],
  });

  final ExternalSettingsOverrides overrides;
  final List<McpServerConfig> mcpServers;
  final List<ExternalToolHook> hooks;

  static const empty = ExternalSettingsSnapshot();
}

class ExternalSettingsOverrides {
  const ExternalSettingsOverrides({
    this.baseUrl,
    this.model,
    this.apiKey,
    this.temperature,
    this.maxTokens,
    this.reasoningEffort,
    this.mcpEnabled,
    this.externalToolHooksEnabled,
    this.assistantMode,
  });

  final String? baseUrl;
  final String? model;
  final String? apiKey;
  final double? temperature;
  final int? maxTokens;
  final ReasoningEffortPreference? reasoningEffort;
  final bool? mcpEnabled;
  final bool? externalToolHooksEnabled;
  final AssistantMode? assistantMode;

  AppSettings applyTo(AppSettings settings) {
    return settings.copyWith(
      baseUrl: baseUrl ?? settings.baseUrl,
      model: model ?? settings.model,
      apiKey: apiKey ?? settings.apiKey,
      temperature: temperature ?? settings.temperature,
      maxTokens: maxTokens ?? settings.maxTokens,
      reasoningEffort: reasoningEffort ?? settings.reasoningEffort,
      mcpEnabled: mcpEnabled ?? settings.mcpEnabled,
      externalToolHooksEnabled:
          externalToolHooksEnabled ?? settings.externalToolHooksEnabled,
      assistantMode: assistantMode ?? settings.assistantMode,
    );
  }
}

class ExternalSettingsService {
  static const String cavernoConfigSourceId = 'external:caverno-config';
  static const String agentKbPresetSourceId = 'preset:agent-kb';
  static const List<String> agentKbHookEvents = [
    'SessionStart',
    'UserPromptSubmit',
    'PostToolUse',
    'PostToolUseFailure',
    'PreCompact',
    'PostCompact',
    'SubagentStop',
    'Stop',
    'SessionEnd',
  ];

  Future<AppSettings> sync(AppSettings settings) async {
    if (!settings.externalSettingsSyncEnabled ||
        !settings.hasExternalSettingsPath) {
      return settings;
    }

    final snapshot = await loadConfig(settings.normalizedExternalSettingsPath);
    return applySnapshot(settings, snapshot);
  }

  Future<ExternalSettingsSnapshot> loadConfig(String path) async {
    final expandedPath = expandUserPath(path);
    if (expandedPath.isEmpty) {
      return ExternalSettingsSnapshot.empty;
    }
    final file = File(expandedPath);
    if (!await file.exists()) {
      appLog('[ExternalSettings] Skipping missing $path');
      return ExternalSettingsSnapshot.empty;
    }

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        appLog('[ExternalSettings] Ignored non-object config $path');
        return ExternalSettingsSnapshot.empty;
      }
      return _snapshotFromJson(decoded);
    } catch (error, stackTrace) {
      appLog('[ExternalSettings] Failed to load $path: $error');
      appLog('[ExternalSettings] $stackTrace');
      return ExternalSettingsSnapshot.empty;
    }
  }

  AppSettings applySnapshot(
    AppSettings settings,
    ExternalSettingsSnapshot snapshot,
  ) {
    final mergedServers = _dedupeServers([
      ...settings.configuredMcpServers.where(
        (server) => server.sourceId != cavernoConfigSourceId,
      ),
      ...snapshot.mcpServers,
    ]);
    final mergedHooks = _dedupeHooks([
      ...settings.externalToolHooks.where(
        (hook) => hook.sourceId != cavernoConfigSourceId,
      ),
      ...snapshot.hooks,
    ]);
    final httpServers = mergedServers.where(
      (server) => server.type == McpServerType.http,
    );
    final activeUrls = AppSettings.activeMcpUrlsFromServers(httpServers);

    return snapshot.overrides
        .applyTo(settings)
        .copyWith(
          mcpUrl: activeUrls.isEmpty ? '' : activeUrls.first,
          mcpUrls: activeUrls,
          mcpServers: mergedServers,
          externalToolHooks: mergedHooks,
        );
  }

  AppSettings applyAgentKbPreset(
    AppSettings settings, {
    String wrapperPath = '~/.local/bin/agent-kb-local',
    String kbBaseDir = '~/.kb',
  }) {
    final wrapper = expandUserPath(wrapperPath);
    final kbBase = expandUserPath(kbBaseDir);
    final env = {'KB_BASE_DIR': kbBase};
    final servers = _dedupeServers([
      ...settings.configuredMcpServers.where(
        (server) => server.sourceId != agentKbPresetSourceId,
      ),
      McpServerConfig(
        enabled: true,
        type: McpServerType.stdio,
        trustState: McpServerTrustState.trusted,
        command: wrapper,
        args: const ['mcp'],
        env: env,
        sourceId: agentKbPresetSourceId,
      ),
    ]);
    final hooks = _dedupeHooks([
      ...settings.externalToolHooks.where(
        (hook) => hook.sourceId != agentKbPresetSourceId,
      ),
      for (final event in agentKbHookEvents)
        ExternalToolHook(
          id: 'agent-kb:$event',
          enabled: true,
          event: event,
          command: wrapper,
          args: const ['hook', '--agent', 'codex'],
          env: env,
          sourceId: agentKbPresetSourceId,
        ),
    ]);
    final httpServers = servers.where(
      (server) => server.type == McpServerType.http,
    );
    final activeUrls = AppSettings.activeMcpUrlsFromServers(httpServers);

    return settings.copyWith(
      externalSettingsSyncEnabled: true,
      externalSettingsPath: settings.hasExternalSettingsPath
          ? settings.normalizedExternalSettingsPath
          : AppSettings.defaultExternalSettingsPath,
      externalToolHooksEnabled: true,
      mcpEnabled: true,
      mcpUrl: activeUrls.isEmpty ? '' : activeUrls.first,
      mcpUrls: activeUrls,
      mcpServers: servers,
      externalToolHooks: hooks,
    );
  }

  ExternalSettingsSnapshot _snapshotFromJson(Map<String, dynamic> root) {
    final overrides = _overridesFromMap(root['settings']);
    final servers = _serversFromRoot(root['mcpServers']);
    final hooks = _hooksFromRoot(root['hooks']);
    return ExternalSettingsSnapshot(
      overrides: overrides,
      mcpServers: servers,
      hooks: hooks,
    );
  }

  ExternalSettingsOverrides _overridesFromMap(Object? value) {
    if (value is! Map) {
      return const ExternalSettingsOverrides();
    }
    final map = Map<String, dynamic>.from(value);
    return ExternalSettingsOverrides(
      baseUrl: _nonEmptyString(map['baseUrl']),
      model: _nonEmptyString(map['model']),
      apiKey: _nonEmptyString(map['apiKey']),
      temperature: _doubleValue(map['temperature']),
      maxTokens: _intValue(map['maxTokens']),
      reasoningEffort: _reasoningEffortValue(map['reasoningEffort']),
      mcpEnabled: _boolValue(map['mcpEnabled']),
      externalToolHooksEnabled: _boolValue(map['externalToolHooksEnabled']),
      assistantMode: _assistantModeValue(map['assistantMode']),
    );
  }

  List<McpServerConfig> _serversFromRoot(Object? value) {
    final servers = <McpServerConfig>[];
    var index = 0;
    if (value is List) {
      for (final item in value) {
        final server = _serverFromMap(item, fallbackId: '$index');
        if (server != null) {
          servers.add(server);
        }
        index++;
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        final server = _serverFromMap(
          entry.value,
          fallbackId: entry.key.toString(),
        );
        if (server != null) {
          servers.add(server);
        }
      }
    }
    return _dedupeServers(servers);
  }

  McpServerConfig? _serverFromMap(Object? value, {required String fallbackId}) {
    if (value is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(value);
    final command = _nonEmptyString(map['command']);
    final url = _nonEmptyString(map['url']);
    final type = _mcpServerTypeValue(map['type'], command: command, url: url);
    final server = switch (type) {
      McpServerType.stdio => McpServerConfig(
        enabled: _boolValue(map['enabled']) ?? true,
        type: McpServerType.stdio,
        trustState:
            _mcpTrustStateValue(map['trustState']) ??
            McpServerTrustState.trusted,
        command: command == null ? '' : expandUserPath(command),
        args: _stringListValue(map['args']),
        env: _stringMapValue(map['env']),
        sourceId: cavernoConfigSourceId,
      ),
      McpServerType.http => McpServerConfig(
        enabled: _boolValue(map['enabled']) ?? true,
        type: McpServerType.http,
        trustState:
            _mcpTrustStateValue(map['trustState']) ??
            McpServerTrustState.trusted,
        url: url ?? '',
        sourceId: cavernoConfigSourceId,
      ),
    };
    if (!server.isValid) {
      appLog('[ExternalSettings] Ignored invalid MCP server $fallbackId');
      return null;
    }
    return server;
  }

  List<ExternalToolHook> _hooksFromRoot(Object? value) {
    final hooks = <ExternalToolHook>[];
    if (value is List) {
      for (final item in value) {
        final hook = _hookFromMap(
          item,
          fallbackEvent: null,
          index: hooks.length,
        );
        if (hook != null) {
          hooks.add(hook);
        }
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        final raw = entry.value;
        final event = entry.key.toString();
        if (raw is List) {
          for (final item in raw) {
            final hook = _hookFromMap(
              item,
              fallbackEvent: event,
              index: hooks.length,
            );
            if (hook != null) {
              hooks.add(hook);
            }
          }
        } else {
          final hook = _hookFromMap(
            raw,
            fallbackEvent: event,
            index: hooks.length,
          );
          if (hook != null) {
            hooks.add(hook);
          }
        }
      }
    }
    return _dedupeHooks(hooks);
  }

  ExternalToolHook? _hookFromMap(
    Object? value, {
    required String? fallbackEvent,
    required int index,
  }) {
    if (value is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(value);
    final event = _nonEmptyString(map['event']) ?? fallbackEvent ?? '';
    final command = _nonEmptyString(map['command']);
    final hook = ExternalToolHook(
      id: '$cavernoConfigSourceId:hook:$event:$index',
      enabled: _boolValue(map['enabled']) ?? true,
      event: event,
      command: command == null ? '' : expandUserPath(command),
      args: _stringListValue(map['args']),
      env: _stringMapValue(map['env']),
      sourceId: cavernoConfigSourceId,
    );
    if (!hook.isUsable) {
      appLog('[ExternalSettings] Ignored invalid hook $index');
      return null;
    }
    return hook;
  }

  McpServerType _mcpServerTypeValue(
    Object? value, {
    required String? command,
    required String? url,
  }) {
    final type = _nonEmptyString(value)?.toLowerCase();
    if (type == 'stdio') {
      return McpServerType.stdio;
    }
    if (type == 'http') {
      return McpServerType.http;
    }
    if (command != null) {
      return McpServerType.stdio;
    }
    if (url != null) {
      return McpServerType.http;
    }
    return McpServerType.http;
  }

  McpServerTrustState? _mcpTrustStateValue(Object? value) {
    final name = _nonEmptyString(value)?.toLowerCase();
    return switch (name) {
      'pending' => McpServerTrustState.pending,
      'trusted' => McpServerTrustState.trusted,
      'blocked' => McpServerTrustState.blocked,
      _ => null,
    };
  }

  ReasoningEffortPreference? _reasoningEffortValue(Object? value) {
    final name = _nonEmptyString(value)?.toLowerCase();
    return switch (name) {
      'automatic' => ReasoningEffortPreference.automatic,
      'low' => ReasoningEffortPreference.low,
      'medium' => ReasoningEffortPreference.medium,
      'high' => ReasoningEffortPreference.high,
      _ => null,
    };
  }

  AssistantMode? _assistantModeValue(Object? value) {
    final name = _nonEmptyString(value)?.toLowerCase();
    return switch (name) {
      'general' => AssistantMode.general,
      'coding' => AssistantMode.coding,
      'plan' => AssistantMode.plan,
      _ => null,
    };
  }

  static List<McpServerConfig> _dedupeServers(
    Iterable<McpServerConfig> servers,
  ) {
    final result = <McpServerConfig>[];
    final seen = <String>{};
    for (final server in servers) {
      final normalized = server.type == McpServerType.http
          ? server.copyWith(
              url: server.normalizedUrl,
              sourceId: server.sourceId.trim(),
            )
          : server.copyWith(
              command: server.normalizedCommand,
              env: server.normalizedEnv,
              sourceId: server.sourceId.trim(),
            );
      if (!normalized.isValid) continue;
      if (!seen.add(normalized.trustIdentity)) continue;
      result.add(normalized);
    }
    return result;
  }

  static List<ExternalToolHook> _dedupeHooks(Iterable<ExternalToolHook> hooks) {
    final result = <ExternalToolHook>[];
    final seen = <String>{};
    for (final hook in hooks) {
      final normalized = hook.normalizedForPersistence();
      if (!normalized.isUsable) continue;
      if (!seen.add(normalized.identity)) continue;
      result.add(normalized);
    }
    return result;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool? _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return null;
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static double? _doubleValue(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  static List<String> _stringListValue(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, String> _stringMapValue(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    final entries =
        value.entries
            .map(
              (entry) => MapEntry(
                entry.key.toString().trim(),
                expandUserPath(entry.value?.toString() ?? ''),
              ),
            )
            .where((entry) => entry.key.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, String>.fromEntries(entries);
  }

  static String expandUserPath(String path) {
    final trimmed = path.trim();
    if (trimmed == '~') {
      return Platform.environment['HOME'] ?? trimmed;
    }
    if (trimmed.startsWith('~/')) {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        return trimmed;
      }
      return '$home/${trimmed.substring(2)}';
    }
    return trimmed;
  }
}
