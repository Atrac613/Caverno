import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/settings/data/external_settings_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  late Directory tempDir;
  late ExternalSettingsService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'caverno_external_settings_test_',
    );
    service = ExternalSettingsService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads Caverno JSON settings, MCP servers, and hooks', () async {
    final config = File('${tempDir.path}/config.json');
    await config.writeAsString(
      jsonEncode({
        'version': 1,
        'settings': {
          'baseUrl': 'http://localhost:4321/v1',
          'model': 'local/test-model',
          'apiKey': 'test-key',
          'temperature': 0.2,
          'maxTokens': 2048,
          'reasoningEffort': 'high',
          'mcpEnabled': true,
          'externalToolHooksEnabled': true,
          'assistantMode': 'coding',
        },
        'mcpServers': [
          {
            'type': 'stdio',
            'command': '${tempDir.path}/agent-kb-local',
            'args': ['mcp'],
            'env': {'KB_BASE_DIR': '${tempDir.path}/kb'},
          },
        ],
        'hooks': [
          {
            'event': 'UserPromptSubmit',
            'command': '${tempDir.path}/agent-kb-local',
            'args': ['hook', '--agent', 'codex'],
            'env': {'KB_BASE_DIR': '${tempDir.path}/kb'},
          },
        ],
      }),
    );

    final snapshot = await service.loadConfig(config.path);
    final applied = snapshot.overrides.applyTo(AppSettings.defaults());

    expect(applied.baseUrl, 'http://localhost:4321/v1');
    expect(applied.model, 'local/test-model');
    expect(applied.apiKey, 'test-key');
    expect(applied.temperature, 0.2);
    expect(applied.maxTokens, 2048);
    expect(applied.reasoningEffort, ReasoningEffortPreference.high);
    expect(applied.mcpEnabled, isTrue);
    expect(applied.externalToolHooksEnabled, isTrue);
    expect(applied.assistantMode, AssistantMode.coding);

    expect(snapshot.mcpServers, hasLength(1));
    final server = snapshot.mcpServers.single;
    expect(server.type, McpServerType.stdio);
    expect(server.command, '${tempDir.path}/agent-kb-local');
    expect(server.args, ['mcp']);
    expect(server.env, {'KB_BASE_DIR': '${tempDir.path}/kb'});
    expect(server.sourceId, ExternalSettingsService.cavernoConfigSourceId);
    expect(server.isTrusted, isTrue);

    expect(snapshot.hooks, hasLength(1));
    final hook = snapshot.hooks.single;
    expect(hook.event, 'UserPromptSubmit');
    expect(hook.command, '${tempDir.path}/agent-kb-local');
    expect(hook.args, ['hook', '--agent', 'codex']);
    expect(hook.sourceId, ExternalSettingsService.cavernoConfigSourceId);
  });

  test(
    'sync replaces managed Caverno config entries without duplicating',
    () async {
      final config = File('${tempDir.path}/config.json');
      await config.writeAsString(
        jsonEncode({
          'mcpServers': {
            'agent-kb': {
              'type': 'stdio',
              'command': '${tempDir.path}/agent-kb-local',
              'args': ['mcp'],
            },
          },
          'hooks': {
            'Stop': {
              'command': '${tempDir.path}/agent-kb-local',
              'args': ['hook', '--agent', 'codex'],
            },
          },
        }),
      );
      final settings = AppSettings.defaults().copyWith(
        externalSettingsSyncEnabled: true,
        externalSettingsPath: config.path,
        mcpServers: const [
          McpServerConfig(url: 'http://localhost:8081', enabled: true),
          McpServerConfig(
            type: McpServerType.stdio,
            command: '/old/agent-kb-local',
            args: ['mcp'],
            sourceId: ExternalSettingsService.cavernoConfigSourceId,
          ),
        ],
        externalToolHooks: const [
          ExternalToolHook(
            id: 'old-stop',
            event: 'Stop',
            command: '/old/agent-kb-local',
            sourceId: ExternalSettingsService.cavernoConfigSourceId,
          ),
        ],
      );

      final first = await service.sync(settings);
      final second = await service.sync(first);

      final managedServers = second.configuredMcpServers.where(
        (server) =>
            server.sourceId == ExternalSettingsService.cavernoConfigSourceId,
      );
      expect(managedServers, hasLength(1));
      expect(managedServers.single.command, '${tempDir.path}/agent-kb-local');
      expect(
        second.configuredMcpServers.any(
          (server) => server.normalizedUrl == 'http://localhost:8081',
        ),
        isTrue,
      );

      final managedHooks = second.externalToolHooks.where(
        (hook) =>
            hook.sourceId == ExternalSettingsService.cavernoConfigSourceId,
      );
      expect(managedHooks, hasLength(1));
      expect(managedHooks.single.command, '${tempDir.path}/agent-kb-local');
    },
  );

  test(
    'missing config clears previously managed Caverno config entries',
    () async {
      final settings = AppSettings.defaults().copyWith(
        externalSettingsSyncEnabled: true,
        externalSettingsPath: '${tempDir.path}/missing.json',
        mcpServers: const [
          McpServerConfig(url: 'http://localhost:8081', enabled: true),
          McpServerConfig(
            type: McpServerType.stdio,
            command: '/old/agent-kb-local',
            args: ['mcp'],
            sourceId: ExternalSettingsService.cavernoConfigSourceId,
          ),
        ],
        externalToolHooks: const [
          ExternalToolHook(
            id: 'old-stop',
            event: 'Stop',
            command: '/old/agent-kb-local',
            sourceId: ExternalSettingsService.cavernoConfigSourceId,
          ),
        ],
      );

      final synced = await service.sync(settings);

      expect(
        synced.configuredMcpServers.where(
          (server) =>
              server.sourceId == ExternalSettingsService.cavernoConfigSourceId,
        ),
        isEmpty,
      );
      expect(
        synced.externalToolHooks.where(
          (hook) =>
              hook.sourceId == ExternalSettingsService.cavernoConfigSourceId,
        ),
        isEmpty,
      );
    },
  );

  test('agent-kb preset enables sync, hooks, and stdio MCP env', () {
    final settings = service.applyAgentKbPreset(
      AppSettings.defaults(),
      wrapperPath: '${tempDir.path}/agent-kb-local',
      kbBaseDir: '${tempDir.path}/kb',
    );

    expect(settings.externalSettingsSyncEnabled, isTrue);
    expect(
      settings.externalSettingsPath,
      AppSettings.defaultExternalSettingsPath,
    );
    expect(settings.externalToolHooksEnabled, isTrue);
    expect(
      settings.configuredMcpServers.any(
        (server) =>
            server.command == '${tempDir.path}/agent-kb-local' &&
            server.args.single == 'mcp' &&
            server.env['KB_BASE_DIR'] == '${tempDir.path}/kb',
      ),
      isTrue,
    );
    expect(
      settings.enabledExternalToolHooksFor('UserPromptSubmit').single.args,
      ['hook', '--agent', 'codex'],
    );
  });
}
