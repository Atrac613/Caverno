import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/entities/model_catalog_entry.dart';

class ModelRemoteDataSource {
  ModelRemoteDataSource({String? baseUrl, String? apiKey, http.Client? client})
    : _baseUrl = baseUrl?.trim().isEmpty ?? true
          ? ApiConstants.defaultBaseUrl
          : baseUrl!.trim(),
      _apiKey = apiKey ?? ApiConstants.defaultApiKey,
      _client = client ?? http.Client();

  static const _contextWindowKeys = <String>{
    'context_length',
    'contextLength',
    'context_window',
    'contextWindow',
    'max_context_length',
    'maxContextLength',
    'max_model_len',
    'maxModelLen',
    'n_ctx',
    'nCtx',
  };

  static const _metadataContainerKeys = <String>{
    'metadata',
    'capabilities',
    'config',
    'details',
    'info',
    'parameters',
  };

  static const _nativeMetadataTimeout = Duration(seconds: 2);

  final String _baseUrl;
  final String _apiKey;
  final http.Client _client;

  Future<List<String>> listModelIds() async {
    final catalog = await listModelCatalog();
    final ids = catalog.map((model) => model.id).toSet().toList()..sort();

    if (ids.isEmpty) {
      throw Exception('No available models could be retrieved');
    }

    return ids;
  }

  Future<List<ModelCatalogEntry>> listModelCatalog({
    String? selectedModelId,
  }) async {
    final selectedModel = _normalizeModelId(selectedModelId);
    Object? primaryError;
    var catalog = const <ModelCatalogEntry>[];

    try {
      catalog = await _fetchOpenAiCatalog();
    } catch (error) {
      primaryError = error;
    }

    List<ModelCatalogEntry>? lmStudioCatalog;
    Future<List<ModelCatalogEntry>> loadLmStudioCatalog() async {
      return lmStudioCatalog ??= await _fetchLmStudioCatalog(
        selectedModelId: selectedModel,
      );
    }

    if (catalog.isEmpty) {
      catalog = await loadLmStudioCatalog();
    } else if (_needsSelectedContextMetadata(catalog, selectedModel)) {
      final nativeCatalog = await loadLmStudioCatalog();
      catalog = _mergeCatalogContext(
        catalog,
        nativeCatalog,
        selectedModelId: selectedModel,
      );
    }

    if (_needsSelectedContextMetadata(catalog, selectedModel)) {
      final tokens = await _fetchLlamaCppContextWindowTokens(
        selectedModelId: selectedModel,
      );
      if (tokens != null) {
        catalog = _mergeSingleContextWindow(
          catalog,
          contextWindowTokens: tokens,
          selectedModelId: selectedModel,
        );
      }
    }

    if (catalog.isEmpty) {
      if (primaryError != null) {
        throw Exception(
          'No available models could be retrieved: $primaryError',
        );
      }
      throw Exception('No available models could be retrieved');
    }

    return _sortedUniqueCatalog(catalog);
  }

  Future<List<ModelCatalogEntry>> _fetchOpenAiCatalog() async {
    final response = await _client.get(_modelsUri(), headers: _headers());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to retrieve models (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Model list response was not a JSON object');
    }

    return parseModelCatalogResponse(decoded);
  }

  static List<ModelCatalogEntry> parseModelCatalogResponse(
    Map<String, dynamic> json,
  ) {
    final data = json['data'];
    if (data is! List) {
      return const [];
    }

    final entriesById = <String, ModelCatalogEntry>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final id = _readString(item, 'id')?.trim();
      if (id == null || id.isEmpty) {
        continue;
      }

      final entry = ModelCatalogEntry(
        id: id,
        ownedBy: _readString(item, 'owned_by') ?? _readString(item, 'ownedBy'),
        contextWindowTokens: _readContextWindowTokens(item),
      );
      final existing = entriesById[id];
      if (existing == null ||
          existing.contextWindowTokens == null &&
              entry.contextWindowTokens != null) {
        entriesById[id] = entry;
      }
    }

    return entriesById.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  static List<ModelCatalogEntry> parseLmStudioModelCatalogResponse(
    Map<String, dynamic> json, {
    String? selectedModelId,
  }) {
    final models = json['models'];
    if (models is! List) {
      return const [];
    }

    final selectedModel = _normalizeModelId(selectedModelId);
    final entriesById = <String, ModelCatalogEntry>{};
    for (final item in models) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final type = _readString(item, 'type')?.trim().toLowerCase();
      if (type == 'embedding') {
        continue;
      }

      final ownedBy = _readString(item, 'publisher');
      final modelKey = _normalizeModelId(_readString(item, 'key'));
      final loadedInstances = item['loaded_instances'];
      final selectedLoadedContext = _readSelectedLmStudioLoadedContext(
        loadedInstances,
        selectedModel,
      );
      final loadedContext =
          selectedLoadedContext ??
          _readFirstLmStudioLoadedContext(loadedInstances);
      final modelContext =
          loadedContext ?? _parsePositiveInt(item['max_context_length']);

      if (modelKey != null) {
        _putPreferredEntry(
          entriesById,
          ModelCatalogEntry(
            id: modelKey,
            ownedBy: ownedBy,
            contextWindowTokens: modelContext,
          ),
        );
      }

      if (loadedInstances is List) {
        for (final loadedInstance in loadedInstances) {
          if (loadedInstance is! Map<String, dynamic>) {
            continue;
          }
          final instanceId = _normalizeModelId(
            _readString(loadedInstance, 'id'),
          );
          if (instanceId == null) {
            continue;
          }
          _putPreferredEntry(
            entriesById,
            ModelCatalogEntry(
              id: instanceId,
              ownedBy: ownedBy,
              contextWindowTokens:
                  _readContextWindowTokens(loadedInstance) ?? modelContext,
            ),
          );
        }
      }
    }

    return entriesById.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  static int? parseLlamaCppPropsContextWindowTokens(Map<String, dynamic> json) {
    final defaultSettings = json['default_generation_settings'];
    if (defaultSettings is Map<String, dynamic>) {
      return _readContextWindowTokens(defaultSettings) ??
          _readContextWindowTokens(json);
    }
    return _readContextWindowTokens(json);
  }

  static int? parseLlamaCppSlotsContextWindowTokens(Object? json) {
    if (json is! List) {
      return null;
    }

    final contexts = <int>{};
    for (final item in json) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final context = _readContextWindowTokens(item);
      if (context != null) {
        contexts.add(context);
      }
    }

    return contexts.length == 1 ? contexts.single : null;
  }

  Future<List<ModelCatalogEntry>> _fetchLmStudioCatalog({
    required String? selectedModelId,
  }) async {
    final decoded = await _tryGetJson(_lmStudioModelsUri());
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }
    return parseLmStudioModelCatalogResponse(
      decoded,
      selectedModelId: selectedModelId,
    );
  }

  Future<int?> _fetchLlamaCppContextWindowTokens({
    required String? selectedModelId,
  }) async {
    final propsWithModel = selectedModelId == null
        ? null
        : await _tryGetJson(
            _llamaCppPropsUri(selectedModelId: selectedModelId),
          );
    final propsWithModelContext = propsWithModel is Map<String, dynamic>
        ? parseLlamaCppPropsContextWindowTokens(propsWithModel)
        : null;
    if (propsWithModelContext != null) {
      return propsWithModelContext;
    }

    final props = await _tryGetJson(_llamaCppPropsUri());
    final propsContext = props is Map<String, dynamic>
        ? parseLlamaCppPropsContextWindowTokens(props)
        : null;
    if (propsContext != null) {
      return propsContext;
    }

    final slots = await _tryGetJson(_llamaCppSlotsUri());
    return parseLlamaCppSlotsContextWindowTokens(slots);
  }

  Uri _modelsUri() {
    final normalized = _stripTrailingSlash(_baseUrl);
    if (normalized.endsWith('/models')) {
      return Uri.parse(normalized);
    }
    return Uri.parse('$normalized/models');
  }

  Uri _lmStudioModelsUri() {
    return _nativeUri('/api/v1/models');
  }

  Uri _llamaCppPropsUri({String? selectedModelId}) {
    return _nativeUri(
      '/props',
      queryParameters: selectedModelId == null
          ? null
          : <String, String>{'model': selectedModelId},
    );
  }

  Uri _llamaCppSlotsUri() {
    return _nativeUri('/slots');
  }

  Uri _nativeUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '${_nativeRootBaseUrl()}$normalizedPath',
    ).replace(queryParameters: queryParameters);
  }

  String _nativeRootBaseUrl() {
    final normalized = _stripTrailingSlash(_baseUrl);
    if (normalized.endsWith('/v1')) {
      return normalized.substring(0, normalized.length - '/v1'.length);
    }
    return normalized;
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Accept': 'application/json'};
    final apiKey = _apiKey.trim();
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  Future<Object?> _tryGetJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(_nativeMetadataTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    } on TimeoutException {
      return null;
    } on Object {
      return null;
    }
  }

  static String? _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value : null;
  }

  static String _stripTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String? _normalizeModelId(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static int? _readContextWindowTokens(Map<String, dynamic> json) {
    for (final source in _metadataSources(json)) {
      for (final key in _contextWindowKeys) {
        final tokens = _parsePositiveInt(source[key]);
        if (tokens != null) {
          return tokens;
        }
      }
    }
    return null;
  }

  static int? _readSelectedLmStudioLoadedContext(
    Object? loadedInstances,
    String? selectedModelId,
  ) {
    if (loadedInstances is! List || selectedModelId == null) {
      return null;
    }

    for (final loadedInstance in loadedInstances) {
      if (loadedInstance is! Map<String, dynamic>) {
        continue;
      }
      if (_readString(loadedInstance, 'id')?.trim() != selectedModelId) {
        continue;
      }
      final context = _readContextWindowTokens(loadedInstance);
      if (context != null) {
        return context;
      }
    }
    return null;
  }

  static int? _readFirstLmStudioLoadedContext(Object? loadedInstances) {
    if (loadedInstances is! List) {
      return null;
    }

    for (final loadedInstance in loadedInstances) {
      if (loadedInstance is! Map<String, dynamic>) {
        continue;
      }
      final context = _readContextWindowTokens(loadedInstance);
      if (context != null) {
        return context;
      }
    }
    return null;
  }

  static Iterable<Map<String, dynamic>> _metadataSources(
    Map<String, dynamic> json,
  ) sync* {
    yield json;
    for (final key in _metadataContainerKeys) {
      final value = json[key];
      if (value is Map<String, dynamic>) {
        yield value;
      }
    }
  }

  static int? _parsePositiveInt(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is num && value.isFinite) {
      final rounded = value.round();
      return rounded > 0 ? rounded : null;
    }
    if (value is String) {
      final normalized = value.trim();
      if (!RegExp(r'^\d+$').hasMatch(normalized)) {
        return null;
      }
      final parsed = int.tryParse(normalized);
      return parsed != null && parsed > 0 ? parsed : null;
    }
    return null;
  }

  static bool _needsSelectedContextMetadata(
    List<ModelCatalogEntry> catalog,
    String? selectedModelId,
  ) {
    if (selectedModelId == null) {
      return catalog.isEmpty;
    }
    for (final entry in catalog) {
      if (entry.id == selectedModelId) {
        return entry.contextWindowTokens == null;
      }
    }
    return true;
  }

  static List<ModelCatalogEntry> _mergeCatalogContext(
    List<ModelCatalogEntry> catalog,
    List<ModelCatalogEntry> metadataCatalog, {
    required String? selectedModelId,
  }) {
    if (metadataCatalog.isEmpty) {
      return catalog;
    }

    final metadataById = <String, ModelCatalogEntry>{
      for (final entry in metadataCatalog) entry.id: entry,
    };
    final merged = <ModelCatalogEntry>[];
    var selectedModelMerged = selectedModelId == null;
    for (final entry in catalog) {
      final metadata = metadataById[entry.id];
      if (entry.id == selectedModelId) {
        selectedModelMerged = true;
      }
      merged.add(
        entry.contextWindowTokens == null &&
                metadata?.contextWindowTokens != null
            ? entry.copyWith(
                ownedBy: entry.ownedBy ?? metadata!.ownedBy,
                contextWindowTokens: metadata!.contextWindowTokens,
              )
            : entry,
      );
    }

    final selectedMetadata = selectedModelId == null
        ? null
        : metadataById[selectedModelId];
    if (!selectedModelMerged && selectedMetadata != null) {
      merged.add(selectedMetadata);
    }
    return _sortedUniqueCatalog(merged);
  }

  static List<ModelCatalogEntry> _mergeSingleContextWindow(
    List<ModelCatalogEntry> catalog, {
    required int contextWindowTokens,
    required String? selectedModelId,
  }) {
    if (selectedModelId == null) {
      if (catalog.length == 1) {
        return [
          catalog.single.copyWith(contextWindowTokens: contextWindowTokens),
        ];
      }
      return catalog;
    }

    var foundSelectedModel = false;
    final merged = <ModelCatalogEntry>[];
    for (final entry in catalog) {
      if (entry.id == selectedModelId) {
        foundSelectedModel = true;
        merged.add(entry.copyWith(contextWindowTokens: contextWindowTokens));
      } else {
        merged.add(entry);
      }
    }
    if (!foundSelectedModel) {
      merged.add(
        ModelCatalogEntry(
          id: selectedModelId,
          contextWindowTokens: contextWindowTokens,
        ),
      );
    }
    return _sortedUniqueCatalog(merged);
  }

  static void _putPreferredEntry(
    Map<String, ModelCatalogEntry> entriesById,
    ModelCatalogEntry entry,
  ) {
    final existing = entriesById[entry.id];
    if (existing == null) {
      entriesById[entry.id] = entry;
      return;
    }
    entriesById[entry.id] = existing.copyWith(
      ownedBy: existing.ownedBy ?? entry.ownedBy,
      contextWindowTokens:
          existing.contextWindowTokens ?? entry.contextWindowTokens,
    );
  }

  static List<ModelCatalogEntry> _sortedUniqueCatalog(
    Iterable<ModelCatalogEntry> entries,
  ) {
    final entriesById = <String, ModelCatalogEntry>{};
    for (final entry in entries) {
      _putPreferredEntry(entriesById, entry);
    }
    return entriesById.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }
}
