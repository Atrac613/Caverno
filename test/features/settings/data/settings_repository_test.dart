import 'dart:convert';

import 'package:caverno/features/settings/data/settings_credential_store.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const settingsKey = 'app_settings';
  const llmSessionLogsDefaultOnMigrationKey =
      'migration.enable_llm_session_logs_default_on.v1';

  test('migrates legacy saved session log default to enabled', () async {
    final legacySettings = AppSettings.defaults()
        .copyWith(enableLlmSessionLogs: false)
        .toJson();
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(legacySettings),
    });

    final prefs = await SharedPreferences.getInstance();
    final loaded = SettingsRepository(prefs).load();

    expect(loaded.enableLlmSessionLogs, isTrue);

    await Future<void>.delayed(Duration.zero);
    final persistedJson =
        jsonDecode(prefs.getString(settingsKey)!) as Map<String, dynamic>;
    expect(persistedJson['enableLlmSessionLogs'], isTrue);
    expect(prefs.getBool(llmSessionLogsDefaultOnMigrationKey), isTrue);
  });

  test('preserves a session log opt-out after migration', () async {
    final optedOutSettings = AppSettings.defaults()
        .copyWith(enableLlmSessionLogs: false)
        .toJson();
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(optedOutSettings),
      llmSessionLogsDefaultOnMigrationKey: true,
    });

    final prefs = await SharedPreferences.getInstance();
    final loaded = SettingsRepository(prefs).load();

    expect(loaded.enableLlmSessionLogs, isFalse);
  });

  test('supports a read-only load without persisting migrations', () async {
    final legacySettings = AppSettings.defaults()
        .copyWith(enableLlmSessionLogs: false)
        .toJson();
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(legacySettings),
    });

    final prefs = await SharedPreferences.getInstance();
    final loaded = SettingsRepository(prefs).loadReadOnly();

    expect(loaded.enableLlmSessionLogs, isTrue);
    await Future<void>.delayed(Duration.zero);
    final persistedJson =
        jsonDecode(prefs.getString(settingsKey)!) as Map<String, dynamic>;
    expect(persistedJson['enableLlmSessionLogs'], isFalse);
    expect(prefs.getBool(llmSessionLogsDefaultOnMigrationKey), isNull);
  });

  test('marks the migration complete when saving settings', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final prefs = await SharedPreferences.getInstance();
    await SettingsRepository(
      prefs,
    ).save(AppSettings.defaults().copyWith(enableLlmSessionLogs: false));

    expect(prefs.getBool(llmSessionLogsDefaultOnMigrationKey), isTrue);
    expect(SettingsRepository(prefs).load().enableLlmSessionLogs, isFalse);
  });

  test('stores credential fields only in secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = _MemorySettingsCredentialStore();
    final repository = await SettingsRepository.create(
      prefs,
      credentialStore: store,
    );
    final settings = AppSettings.defaults().copyWith(
      apiKey: 'primary-secret',
      llmEndpoints: const [
        LlmEndpoint(
          id: 'primary',
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'primary-secret',
        ),
        LlmEndpoint(
          id: 'secondary',
          baseUrl: 'https://secondary.example.com/v1',
          apiKey: 'endpoint-secret',
        ),
      ],
      activeLlmEndpointId: 'primary',
      googleChatWebhookUrl: 'https://chat.example.com/secret-webhook',
      feedbackEndpointAuthToken: 'feedback-secret',
      mcpServers: const [
        McpServerConfig(
          url: 'https://mcp.example.com',
          env: {'MCP_TOKEN': 'mcp-secret'},
        ),
      ],
      externalToolHooks: const [
        ExternalToolHook(
          id: 'hook',
          event: 'after_tool',
          command: 'hook-command',
          env: {'HOOK_TOKEN': 'hook-secret'},
        ),
      ],
    );

    await repository.save(settings);

    final persisted = prefs.getString(settingsKey)!;
    for (final secret in const [
      'primary-secret',
      'endpoint-secret',
      'secret-webhook',
      'feedback-secret',
      'mcp-secret',
      'hook-secret',
    ]) {
      expect(persisted, isNot(contains(secret)));
    }
    final persistedJson = jsonDecode(persisted) as Map<String, dynamic>;
    expect(persistedJson['credentialReferences'], isA<Map>());
    expect(
      store.values.values,
      containsAll(<String>[
        'primary-secret',
        'endpoint-secret',
        'https://chat.example.com/secret-webhook',
        'feedback-secret',
        'mcp-secret',
        'hook-secret',
      ]),
    );

    final reloaded = (await SettingsRepository.create(
      prefs,
      credentialStore: store,
    )).load();
    expect(reloaded.apiKey, 'primary-secret');
    expect(reloaded.llmEndpoints[1].apiKey, 'endpoint-secret');
    expect(
      reloaded.googleChatWebhookUrl,
      'https://chat.example.com/secret-webhook',
    );
    expect(reloaded.feedbackEndpointAuthToken, 'feedback-secret');
    expect(reloaded.mcpServers.single.env['MCP_TOKEN'], 'mcp-secret');
    expect(reloaded.externalToolHooks.single.env['HOOK_TOKEN'], 'hook-secret');
  });

  test('migrates legacy cleartext credentials before loading', () async {
    final legacy = AppSettings.defaults().copyWith(
      apiKey: 'legacy-primary-secret',
      feedbackEndpointAuthToken: 'legacy-feedback-secret',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      settingsKey: jsonEncode(legacy.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = _MemorySettingsCredentialStore();

    final repository = await SettingsRepository.create(
      prefs,
      credentialStore: store,
    );

    expect(repository.load().apiKey, 'legacy-primary-secret');
    expect(
      repository.load().feedbackEndpointAuthToken,
      'legacy-feedback-secret',
    );
    final persisted = prefs.getString(settingsKey)!;
    expect(persisted, isNot(contains('legacy-primary-secret')));
    expect(persisted, isNot(contains('legacy-feedback-secret')));
    expect(store.writeCount, 1);
  });

  test('preserves referenced credentials during partial migration', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = _MemorySettingsCredentialStore();
    final repository = await SettingsRepository.create(
      prefs,
      credentialStore: store,
    );
    await repository.save(
      AppSettings.defaults().copyWith(
        apiKey: 'secure-primary-secret',
        llmEndpoints: const [
          LlmEndpoint(
            id: 'primary',
            baseUrl: 'http://localhost:1234/v1',
            apiKey: 'secure-primary-secret',
          ),
        ],
        activeLlmEndpointId: 'primary',
        feedbackEndpointAuthToken: 'secure-feedback-secret',
      ),
    );
    final partiallyMigrated =
        jsonDecode(prefs.getString(settingsKey)!) as Map<String, dynamic>;
    partiallyMigrated['googleChatWebhookUrl'] =
        'https://chat.example.com/legacy-secret';
    (partiallyMigrated['llmEndpoints'] as List).add(
      const LlmEndpoint(
        id: 'legacy-endpoint',
        baseUrl: 'https://legacy.example.com/v1',
        apiKey: 'legacy-endpoint-secret',
      ).toJson(),
    );
    partiallyMigrated['mcpServers'] = const [
      {
        'url': 'https://mcp.example.com',
        'env': {'MCP_TOKEN': 'legacy-mcp-secret'},
      },
    ];
    await prefs.setString(settingsKey, jsonEncode(partiallyMigrated));

    final migrated = await SettingsRepository.create(
      prefs,
      credentialStore: store,
    );

    expect(migrated.load().apiKey, 'secure-primary-secret');
    expect(migrated.load().feedbackEndpointAuthToken, 'secure-feedback-secret');
    expect(
      migrated.load().googleChatWebhookUrl,
      'https://chat.example.com/legacy-secret',
    );
    expect(
      migrated
          .load()
          .llmEndpoints
          .firstWhere((endpoint) => endpoint.id == 'legacy-endpoint')
          .apiKey,
      'legacy-endpoint-secret',
    );
    expect(
      migrated.load().mcpServers.single.env['MCP_TOKEN'],
      'legacy-mcp-secret',
    );
    expect(
      prefs.getString(settingsKey),
      isNot(contains('https://chat.example.com/legacy-secret')),
    );
    expect(prefs.getString(settingsKey), isNot(contains('legacy-mcp-secret')));
  });

  test('removes unreferenced secure credentials after restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = _MemorySettingsCredentialStore();
    final repository = await SettingsRepository.create(
      prefs,
      credentialStore: store,
    );
    await repository.save(
      AppSettings.defaults().copyWith(apiKey: 'active-secret'),
    );
    store.values['settings.orphan.apiKey'] = 'orphan-secret';

    final reloaded = await SettingsRepository.create(
      prefs,
      credentialStore: store,
    );

    expect(reloaded.load().apiKey, 'active-secret');
    expect(store.values.values, isNot(contains('orphan-secret')));
  });

  test(
    'fails closed when secure migration cannot persist credentials',
    () async {
      final legacy = AppSettings.defaults().copyWith(apiKey: 'legacy-secret');
      SharedPreferences.setMockInitialValues(<String, Object>{
        settingsKey: jsonEncode(legacy.toJson()),
      });
      final prefs = await SharedPreferences.getInstance();
      final store = _MemorySettingsCredentialStore(failWrites: true);

      await expectLater(
        SettingsRepository.create(prefs, credentialStore: store),
        throwsStateError,
      );
      expect(prefs.getString(settingsKey), contains('legacy-secret'));
    },
  );

  test('reset clears normal and secure settings', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = _MemorySettingsCredentialStore();
    final repository = await SettingsRepository.create(
      prefs,
      credentialStore: store,
    );
    await repository.save(
      AppSettings.defaults().copyWith(apiKey: 'stored-secret'),
    );

    await repository.reset();

    expect(prefs.getString(settingsKey), isNull);
    expect(store.values, isEmpty);
    expect(store.clearCount, greaterThan(0));
  });
}

final class _MemorySettingsCredentialStore implements SettingsCredentialStore {
  _MemorySettingsCredentialStore({this.failWrites = false});

  final bool failWrites;
  Map<String, String> values = <String, String>{};
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
    values = <String, String>{};
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<void> writeAll(Map<String, String> credentials) async {
    writeCount++;
    if (failWrites) {
      throw StateError('secure storage unavailable');
    }
    values = Map.of(credentials);
  }
}
