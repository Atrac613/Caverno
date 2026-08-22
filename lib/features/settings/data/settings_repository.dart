import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/entities/app_settings.dart';
import 'settings_credential_store.dart';

class SettingsRepository {
  SettingsRepository(this._prefs, {SettingsCredentialStore? credentialStore})
    : _credentialStore = credentialStore,
      _credentials =
          _volatileCredentialsByPreferences[_prefs] ?? const <String, String>{};

  static Future<SettingsRepository> create(
    SharedPreferences prefs, {
    SettingsCredentialStore credentialStore =
        const FlutterSettingsCredentialStore(),
  }) async {
    final repository = SettingsRepository(
      prefs,
      credentialStore: credentialStore,
    );
    await repository.initialize();
    return repository;
  }

  final SharedPreferences _prefs;
  final SettingsCredentialStore? _credentialStore;
  Map<String, String> _credentials;

  static final Expando<Map<String, String>> _volatileCredentialsByPreferences =
      Expando<Map<String, String>>();

  static const _settingsKey = 'app_settings';
  static const _credentialReferencesKey = 'credentialReferences';
  static const _llmSessionLogsDefaultOnMigrationKey =
      'migration.enable_llm_session_logs_default_on.v1';

  Future<void> initialize() async {
    final credentialStore = _credentialStore;
    if (credentialStore == null) return;
    _credentials = await credentialStore.readAll();

    final decoded = _decodeStoredSettings();
    if (decoded == null) return;
    if (!_containsCleartextCredentials(decoded)) {
      await _pruneUnreferencedCredentials(decoded);
      return;
    }

    final legacySettings = AppSettings.fromJson(
      _hydrateCredentials(decoded),
    ).withNormalizedLlmEndpoints();
    await save(legacySettings);
  }

  AppSettings load() => _load(persistMigrations: true);

  /// Reads effective settings without updating migration markers or payloads.
  AppSettings loadReadOnly() => _load(persistMigrations: false);

  AppSettings _load({required bool persistMigrations}) {
    final decoded = _decodeStoredSettings();
    if (decoded == null) {
      return AppSettings.defaults().withNormalizedLlmEndpoints();
    }
    try {
      // Seeds the saved-endpoint list from the primary connection fields on
      // installs that predate multi-endpoint support.
      final settings = AppSettings.fromJson(
        _hydrateCredentials(decoded),
      ).withNormalizedLlmEndpoints();
      if (_shouldEnableSessionLogsForDefaultOnMigration(decoded)) {
        final migrated = settings.copyWith(enableLlmSessionLogs: true);
        if (persistMigrations) {
          _persistMigratedSessionLogDefault(migrated);
        }
        return migrated;
      }
      return settings;
    } catch (_) {
      return AppSettings.defaults().withNormalizedLlmEndpoints();
    }
  }

  Future<void> save(AppSettings settings) async {
    final persistence = _preparePersistence(settings);
    final credentialStore = _credentialStore;
    final needsCredentialCleanup = _credentials.isNotEmpty;
    if (credentialStore != null) {
      await credentialStore.writeAll(<String, String>{
        ..._credentials,
        ...persistence.credentials,
      });
    }
    await _prefs.setBool(_llmSessionLogsDefaultOnMigrationKey, true);
    await _prefs.setString(_settingsKey, jsonEncode(persistence.settingsJson));
    _credentials = persistence.credentials;
    _volatileCredentialsByPreferences[_prefs] = _credentials;
    if (credentialStore != null && needsCredentialCleanup) {
      await credentialStore.writeAll(persistence.credentials);
    }
  }

  Future<void> reset() async {
    await _credentialStore?.clear();
    _credentials = const <String, String>{};
    _volatileCredentialsByPreferences[_prefs] = _credentials;
    await _prefs.remove(_settingsKey);
  }

  Map<String, dynamic>? _decodeStoredSettings() {
    final encoded = _prefs.getString(_settingsKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  bool _containsCleartextCredentials(Map<String, dynamic> json) {
    bool nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;
    bool envHasValues(Object? value) =>
        value is Map && value.values.any(nonEmpty);

    if (nonEmpty(json['apiKey']) ||
        nonEmpty(json['googleChatWebhookUrl']) ||
        nonEmpty(json['feedbackEndpointAuthToken'])) {
      return true;
    }
    for (final field in const <String>[
      'llmEndpoints',
      'llmEndpointProfiles',
      'namedEndpoints',
    ]) {
      for (final endpoint in (json[field] as List? ?? const <Object>[])) {
        if (endpoint is Map && nonEmpty(endpoint['apiKey'])) return true;
      }
    }
    for (final server in (json['mcpServers'] as List? ?? const <Object>[])) {
      if (server is Map && envHasValues(server['env'])) return true;
    }
    for (final hook
        in (json['externalToolHooks'] as List? ?? const <Object>[])) {
      if (hook is Map && envHasValues(hook['env'])) return true;
    }
    return false;
  }

  Future<void> _pruneUnreferencedCredentials(
    Map<String, dynamic> storedJson,
  ) async {
    final rawReferences = storedJson[_credentialReferencesKey];
    if (rawReferences is! Map || _credentials.isEmpty) return;
    final referencedKeys = <String>{};

    void collect(Object? value) {
      if (value is String) {
        referencedKeys.add(value);
      } else if (value is Map) {
        for (final nestedValue in value.values) {
          collect(nestedValue);
        }
      } else if (value is List) {
        for (final nestedValue in value) {
          collect(nestedValue);
        }
      }
    }

    collect(rawReferences);
    final retained = <String, String>{
      for (final entry in _credentials.entries)
        if (referencedKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (retained.length == _credentials.length) return;
    await _credentialStore!.writeAll(retained);
    _credentials = retained;
  }

  Map<String, dynamic> _hydrateCredentials(Map<String, dynamic> storedJson) {
    final hydrated = Map<String, dynamic>.from(storedJson);
    final rawReferences = storedJson[_credentialReferencesKey];
    if (rawReferences is! Map) return hydrated;
    final references = Map<String, dynamic>.from(rawReferences);

    void hydrateScalar(String field) {
      final reference = references[field];
      if (reference is String) {
        hydrated[field] = _credentials[reference] ?? '';
      }
    }

    hydrateScalar('apiKey');
    hydrateScalar('googleChatWebhookUrl');
    hydrateScalar('feedbackEndpointAuthToken');
    hydrated['llmEndpoints'] = _hydrateListField(
      storedJson['llmEndpoints'],
      references['llmEndpoints'],
      secretField: 'apiKey',
    );
    hydrated['mcpServers'] = _hydrateListField(
      storedJson['mcpServers'],
      references['mcpServers'],
      secretField: 'env',
      mapSecret: true,
    );
    hydrated['externalToolHooks'] = _hydrateListField(
      storedJson['externalToolHooks'],
      references['externalToolHooks'],
      secretField: 'env',
      mapSecret: true,
    );
    return hydrated;
  }

  List<dynamic> _hydrateListField(
    Object? rawItems,
    Object? rawReferences, {
    required String secretField,
    bool mapSecret = false,
  }) {
    final items = rawItems is List ? rawItems : const <dynamic>[];
    final references = rawReferences is List
        ? rawReferences
        : const <dynamic>[];
    return <dynamic>[
      for (var index = 0; index < items.length; index++)
        if (items[index] is Map)
          _hydrateListItem(
            Map<String, dynamic>.from(items[index] as Map),
            index < references.length ? references[index] : null,
            secretField: secretField,
            mapSecret: mapSecret,
          )
        else
          items[index],
    ];
  }

  Map<String, dynamic> _hydrateListItem(
    Map<String, dynamic> item,
    Object? rawReference, {
    required String secretField,
    required bool mapSecret,
  }) {
    final hasReference = mapSecret
        ? rawReference is Map && rawReference.isNotEmpty
        : rawReference is String;
    if (!hasReference) return item;
    return <String, dynamic>{
      ...item,
      secretField: _hydrateReferencedValue(rawReference, mapSecret: mapSecret),
    };
  }

  Object _hydrateReferencedValue(
    Object? rawReference, {
    required bool mapSecret,
  }) {
    if (mapSecret) {
      if (rawReference is! Map) return const <String, String>{};
      return <String, String>{
        for (final entry in rawReference.entries)
          if (entry.value is String)
            entry.key.toString(): _credentials[entry.value] ?? '',
      };
    }
    return rawReference is String ? _credentials[rawReference] ?? '' : '';
  }

  _SettingsPersistence _preparePersistence(AppSettings settings) {
    final json =
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;
    final credentials = <String, String>{};
    final references = <String, dynamic>{};
    final generation = const Uuid().v4();

    void extractScalar(String field, String reference) {
      final value = json[field];
      if (value is! String || value.isEmpty) return;
      credentials[reference] = value;
      references[field] = reference;
      json[field] = '';
    }

    extractScalar('apiKey', 'settings.$generation.apiKey');
    extractScalar(
      'googleChatWebhookUrl',
      'settings.$generation.googleChatWebhookUrl',
    );
    extractScalar(
      'feedbackEndpointAuthToken',
      'settings.$generation.feedbackEndpointAuthToken',
    );
    references['llmEndpoints'] = _extractListCredentials(
      json['llmEndpoints'],
      credentials,
      group: '$generation.llmEndpoints',
      secretField: 'apiKey',
    );
    references['mcpServers'] = _extractListCredentials(
      json['mcpServers'],
      credentials,
      group: '$generation.mcpServers',
      secretField: 'env',
      mapSecret: true,
    );
    references['externalToolHooks'] = _extractListCredentials(
      json['externalToolHooks'],
      credentials,
      group: '$generation.externalToolHooks',
      secretField: 'env',
      mapSecret: true,
    );
    json[_credentialReferencesKey] = references;
    return _SettingsPersistence(settingsJson: json, credentials: credentials);
  }

  List<dynamic> _extractListCredentials(
    Object? rawItems,
    Map<String, String> credentials, {
    required String group,
    required String secretField,
    bool mapSecret = false,
  }) {
    if (rawItems is! List) return const <dynamic>[];
    final references = <dynamic>[];
    for (var index = 0; index < rawItems.length; index++) {
      final rawItem = rawItems[index];
      if (rawItem is! Map) {
        references.add(null);
        continue;
      }
      final item = Map<String, dynamic>.from(rawItem);
      final secret = item[secretField];
      if (mapSecret && secret is Map) {
        final itemReferences = <String, String>{};
        for (final entry in secret.entries) {
          final value = entry.value;
          if (value is! String || value.isEmpty) continue;
          final reference = 'settings.$group.$index.$secretField.${entry.key}';
          credentials[reference] = value;
          itemReferences[entry.key.toString()] = reference;
        }
        item[secretField] = const <String, String>{};
        rawItems[index] = item;
        references.add(itemReferences);
        continue;
      }
      if (!mapSecret && secret is String && secret.isNotEmpty) {
        final reference = 'settings.$group.$index.$secretField';
        credentials[reference] = secret;
        item[secretField] = '';
        rawItems[index] = item;
        references.add(reference);
        continue;
      }
      references.add(mapSecret ? const <String, String>{} : null);
    }
    return references;
  }

  bool _shouldEnableSessionLogsForDefaultOnMigration(
    Map<String, dynamic> settingsJson,
  ) {
    if (_prefs.getBool(_llmSessionLogsDefaultOnMigrationKey) == true) {
      return false;
    }
    return settingsJson['enableLlmSessionLogs'] == false;
  }

  void _persistMigratedSessionLogDefault(AppSettings settings) {
    unawaited(_prefs.setBool(_llmSessionLogsDefaultOnMigrationKey, true));
    unawaited(save(settings));
  }
}

final class _SettingsPersistence {
  const _SettingsPersistence({
    required this.settingsJson,
    required this.credentials,
  });

  final Map<String, dynamic> settingsJson;
  final Map<String, String> credentials;
}
