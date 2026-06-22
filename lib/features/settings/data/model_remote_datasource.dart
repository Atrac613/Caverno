import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../domain/entities/local_model_lifecycle.dart';
import '../domain/entities/model_catalog_entry.dart';

class ModelCatalogHttpException implements Exception {
  const ModelCatalogHttpException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Failed to retrieve models ($statusCode)';
}

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
    'num_ctx',
    'numCtx',
    'n_ctx',
    'nCtx',
  };

  static const _metadataContainerKeys = <String>{
    'metadata',
    'capabilities',
    'config',
    'details',
    'info',
    'model_info',
    'parameters',
  };

  static const _nativeMetadataTimeout = Duration(seconds: 2);

  static const _modelLifecycleUnsupportedMessage =
      'Model lifecycle management is not available at this endpoint. '
      'Use llama.cpp router mode with --models-dir, LM Studio v1 REST API, '
      'or Ollama native API endpoints to enable lifecycle controls.';

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
    final isNvidiaNimCloud = ApiConstants.isNvidiaNimCloudBaseUrl(_baseUrl);

    try {
      catalog = await _fetchOpenAiCatalog();
    } catch (error) {
      primaryError = error;
    }

    if (catalog.isEmpty && _canUseNvidiaNimFallback(primaryError)) {
      catalog = nvidiaNimCloudModelCatalog();
    }

    List<ModelCatalogEntry>? lmStudioCatalog;
    Future<List<ModelCatalogEntry>> loadLmStudioCatalog() async {
      return lmStudioCatalog ??= await _fetchLmStudioCatalog(
        selectedModelId: selectedModel,
      );
    }

    if (!isNvidiaNimCloud) {
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
      throw ModelCatalogHttpException(response.statusCode);
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

  static List<ModelCatalogEntry> nvidiaNimCloudModelCatalog() {
    return [
      for (final id in ApiConstants.nvidiaNimModelIds)
        ModelCatalogEntry(id: id, ownedBy: id.split('/').first),
    ];
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

  static LocalModelLifecycleCatalog parseLlamaCppManagedModelCatalogResponse(
    Object? json,
  ) {
    if (json is! Map<String, dynamic>) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Model lifecycle response was not a JSON object.',
      );
    }

    final data = json['data'];
    if (data is! List) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Model lifecycle response did not include a data list.',
      );
    }

    final modelsById = <String, LocalManagedModel>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final id = _normalizeModelId(_readString(item, 'id'));
      if (id == null) {
        continue;
      }
      final status = _readLifecycleStatus(item['status']);
      final model = LocalManagedModel(
        id: id,
        state: status.state,
        statusValue: status.value,
        path: _readString(item, 'path'),
        ownedBy: _readString(item, 'owned_by') ?? _readString(item, 'ownedBy'),
        contextWindowTokens: _readContextWindowTokens(item),
        failed: status.failed,
        exitCode: status.exitCode,
        commandArguments: status.commandArguments,
      );
      modelsById[id] = model;
    }

    if (modelsById.isEmpty) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Model lifecycle response did not include usable model ids.',
      );
    }

    final models = modelsById.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return LocalModelLifecycleCatalog.supported(models: models);
  }

  static LocalModelLifecycleCatalog parseOpenAiManagedModelCatalogResponse(
    Object? json,
  ) {
    if (json is! Map<String, dynamic>) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'OpenAI-compatible lifecycle response was not a JSON object.',
      );
    }

    final data = json['data'];
    if (data is! List) {
      return const LocalModelLifecycleCatalog.unsupported(
        message:
            'OpenAI-compatible lifecycle response did not include a data list.',
      );
    }

    final modelsById = <String, LocalManagedModel>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final id = _normalizeModelId(_readString(item, 'id'));
      if (id == null) {
        continue;
      }
      final status = _readOpenAiLifecycleStatus(item);
      if (status == null) {
        continue;
      }
      modelsById[id] = LocalManagedModel(
        id: id,
        state: status.state,
        statusValue: status.value,
        ownedBy: _readString(item, 'owned_by') ?? _readString(item, 'ownedBy'),
        contextWindowTokens: _readContextWindowTokens(item),
        failed: status.failed,
        exitCode: status.exitCode,
        commandArguments: status.commandArguments,
      );
    }

    if (modelsById.isEmpty) {
      return const LocalModelLifecycleCatalog.unsupported(
        message:
            'OpenAI-compatible model catalog did not include lifecycle status.',
      );
    }

    final models = modelsById.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return LocalModelLifecycleCatalog.supported(models: models);
  }

  static LocalModelLifecycleCatalog parseLmStudioManagedModelCatalogResponse(
    Object? json,
  ) {
    if (json is! Map<String, dynamic>) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'LM Studio lifecycle response was not a JSON object.',
      );
    }

    final models = json['models'];
    if (models is! List) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'LM Studio lifecycle response did not include a models list.',
      );
    }

    final modelsById = <String, LocalManagedModel>{};
    for (final item in models) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final type = _readString(item, 'type')?.trim().toLowerCase();
      if (type == 'embedding') {
        continue;
      }

      final modelKey = _normalizeModelId(_readString(item, 'key'));
      if (modelKey == null) {
        continue;
      }

      final loadedInstances = item['loaded_instances'];
      var addedLoadedInstance = false;
      if (loadedInstances is List) {
        for (final loadedInstance in loadedInstances) {
          if (loadedInstance is! Map<String, dynamic>) {
            continue;
          }
          final instanceId =
              _normalizeModelId(_readString(loadedInstance, 'id')) ?? modelKey;
          modelsById[instanceId] = LocalManagedModel(
            id: instanceId,
            state: LocalModelLifecycleState.loaded,
            statusValue: 'loaded',
            ownedBy: _readString(item, 'publisher'),
            contextWindowTokens:
                _readContextWindowTokens(loadedInstance) ??
                _readContextWindowTokens(item),
            metadataHints: _lmStudioMetadataHints(item),
          );
          addedLoadedInstance = true;
        }
      }

      if (!addedLoadedInstance) {
        modelsById[modelKey] = LocalManagedModel(
          id: modelKey,
          state: LocalModelLifecycleState.unloaded,
          statusValue: 'unloaded',
          ownedBy: _readString(item, 'publisher'),
          contextWindowTokens: _readContextWindowTokens(item),
          metadataHints: _lmStudioMetadataHints(item),
        );
      }
    }

    if (modelsById.isEmpty) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'LM Studio lifecycle response did not include usable models.',
      );
    }

    final localModels = modelsById.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return LocalModelLifecycleCatalog.supported(models: localModels);
  }

  static LocalModelLifecycleCatalog parseOllamaManagedModelCatalogResponse({
    required Object? tagsJson,
    Object? runningJson,
    Map<String, Map<String, dynamic>> showDetailsByModel = const {},
  }) {
    if (tagsJson is! Map<String, dynamic>) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Ollama lifecycle response was not a JSON object.',
      );
    }

    final models = tagsJson['models'];
    if (models is! List) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Ollama lifecycle response did not include a models list.',
      );
    }

    final runningById = _ollamaRunningModelsById(runningJson);
    final modelsById = <String, LocalManagedModel>{};
    for (final item in models) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final id = _normalizeModelId(
        _readString(item, 'model') ?? _readString(item, 'name'),
      );
      if (id == null) {
        continue;
      }

      final running = runningById[id];
      final showDetails = showDetailsByModel[id];
      modelsById[id] = _ollamaManagedModel(
        id: id,
        state: running == null
            ? LocalModelLifecycleState.unloaded
            : LocalModelLifecycleState.loaded,
        statusValue: running == null ? 'unloaded' : 'loaded',
        sources: [item, ?running, ?showDetails],
      );
    }

    for (final entry in runningById.entries) {
      if (modelsById.containsKey(entry.key)) {
        continue;
      }
      final showDetails = showDetailsByModel[entry.key];
      modelsById[entry.key] = _ollamaManagedModel(
        id: entry.key,
        state: LocalModelLifecycleState.loaded,
        statusValue: 'loaded',
        sources: [entry.value, ?showDetails],
      );
    }

    if (modelsById.isEmpty) {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Ollama lifecycle response did not include usable models.',
      );
    }

    final localModels = modelsById.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return LocalModelLifecycleCatalog.supported(models: localModels);
  }

  Future<LocalModelLifecycleCatalog> listLlamaCppManagedModels({
    bool refresh = false,
  }) async {
    try {
      final response = await _client
          .get(_llamaCppRouterModelsUri(refresh: refresh), headers: _headers())
          .timeout(_nativeMetadataTimeout);
      if (_isLifecycleUnsupportedStatus(response.statusCode)) {
        return const LocalModelLifecycleCatalog.unsupported(
          message: _modelLifecycleUnsupportedMessage,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LocalModelLifecycleCatalog.unsupported(
          message: _readHttpErrorMessage(
            response.body,
            fallback:
                'Failed to retrieve managed models (${response.statusCode}).',
          ),
        );
      }
      return parseLlamaCppManagedModelCatalogResponse(
        jsonDecode(response.body),
      );
    } on FormatException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Managed model response was not valid JSON.',
      );
    } on TimeoutException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Timed out while retrieving managed models.',
      );
    } on Object {
      return const LocalModelLifecycleCatalog.unsupported(
        message: _modelLifecycleUnsupportedMessage,
      );
    }
  }

  Future<LocalModelLifecycleCatalog> listOpenAiManagedModels({
    bool refresh = false,
  }) async {
    try {
      final response = await _client
          .get(_modelsUri(), headers: _headers())
          .timeout(_nativeMetadataTimeout);
      if (_isLifecycleUnsupportedStatus(response.statusCode)) {
        return const LocalModelLifecycleCatalog.unsupported(
          message: _modelLifecycleUnsupportedMessage,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LocalModelLifecycleCatalog.unsupported(
          message: _readHttpErrorMessage(
            response.body,
            fallback:
                'Failed to retrieve OpenAI-compatible managed models '
                '(${response.statusCode}).',
          ),
        );
      }
      return parseOpenAiManagedModelCatalogResponse(jsonDecode(response.body));
    } on FormatException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'OpenAI-compatible managed model response was not valid JSON.',
      );
    } on TimeoutException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Timed out while retrieving OpenAI-compatible managed models.',
      );
    } on Object {
      return const LocalModelLifecycleCatalog.unsupported(
        message: _modelLifecycleUnsupportedMessage,
      );
    }
  }

  Future<LocalModelLifecycleCatalog> listLmStudioManagedModels() async {
    try {
      final response = await _client
          .get(_lmStudioModelsUri(), headers: _headers())
          .timeout(_nativeMetadataTimeout);
      if (_isLifecycleUnsupportedStatus(response.statusCode)) {
        return const LocalModelLifecycleCatalog.unsupported(
          message: _modelLifecycleUnsupportedMessage,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LocalModelLifecycleCatalog.unsupported(
          message: _readHttpErrorMessage(
            response.body,
            fallback:
                'Failed to retrieve LM Studio managed models '
                '(${response.statusCode}).',
          ),
        );
      }
      return parseLmStudioManagedModelCatalogResponse(
        jsonDecode(response.body),
      );
    } on FormatException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'LM Studio managed model response was not valid JSON.',
      );
    } on TimeoutException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Timed out while retrieving LM Studio managed models.',
      );
    } on Object {
      return const LocalModelLifecycleCatalog.unsupported(
        message: _modelLifecycleUnsupportedMessage,
      );
    }
  }

  Future<LocalModelLifecycleCatalog> listOllamaManagedModels() async {
    try {
      final response = await _client
          .get(_ollamaTagsUri(), headers: _headers())
          .timeout(_nativeMetadataTimeout);
      if (_isLifecycleUnsupportedStatus(response.statusCode)) {
        return const LocalModelLifecycleCatalog.unsupported(
          message: _modelLifecycleUnsupportedMessage,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LocalModelLifecycleCatalog.unsupported(
          message: _readHttpErrorMessage(
            response.body,
            fallback:
                'Failed to retrieve Ollama managed models '
                '(${response.statusCode}).',
          ),
        );
      }

      final tagsJson = jsonDecode(response.body);
      final runningJson = await _tryGetJson(_ollamaPsUri());
      final showDetailsByModel = await _fetchOllamaShowDetailsByModel(
        _ollamaModelIdsFromTags(tagsJson),
      );
      return parseOllamaManagedModelCatalogResponse(
        tagsJson: tagsJson,
        runningJson: runningJson,
        showDetailsByModel: showDetailsByModel,
      );
    } on FormatException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Ollama managed model response was not valid JSON.',
      );
    } on TimeoutException {
      return const LocalModelLifecycleCatalog.unsupported(
        message: 'Timed out while retrieving Ollama managed models.',
      );
    } on Object {
      return const LocalModelLifecycleCatalog.unsupported(
        message: _modelLifecycleUnsupportedMessage,
      );
    }
  }

  Future<LocalModelLifecycleCatalog> listManagedModels({
    bool refresh = false,
  }) async {
    final openAiCatalog = await listOpenAiManagedModels(refresh: refresh);
    if (openAiCatalog.supported) {
      return openAiCatalog;
    }

    final llamaCppCatalog = await listLlamaCppManagedModels(refresh: refresh);
    if (llamaCppCatalog.supported) {
      return llamaCppCatalog;
    }

    final lmStudioCatalog = await listLmStudioManagedModels();
    if (lmStudioCatalog.supported) {
      return lmStudioCatalog;
    }

    final ollamaCatalog = await listOllamaManagedModels();
    return ollamaCatalog.supported ? ollamaCatalog : llamaCppCatalog;
  }

  Future<LocalModelLifecycleActionResult> loadManagedModel(
    String modelId,
  ) async {
    final llamaCppResult = await loadLlamaCppModel(modelId);
    if (llamaCppResult.supported) {
      return llamaCppResult;
    }
    final lmStudioResult = await loadLmStudioModel(modelId);
    if (lmStudioResult.supported) {
      return lmStudioResult;
    }
    final ollamaResult = await loadOllamaModel(modelId);
    return ollamaResult.supported ? ollamaResult : llamaCppResult;
  }

  Future<LocalModelLifecycleActionResult> unloadManagedModel(
    String modelId,
  ) async {
    final llamaCppResult = await unloadLlamaCppModel(modelId);
    if (llamaCppResult.supported) {
      return llamaCppResult;
    }
    final lmStudioResult = await unloadLmStudioModel(modelId);
    if (lmStudioResult.supported) {
      return lmStudioResult;
    }
    final ollamaResult = await unloadOllamaModel(modelId);
    return ollamaResult.supported ? ollamaResult : llamaCppResult;
  }

  Future<LocalModelLifecycleActionResult> loadLlamaCppModel(String modelId) {
    return _postManagedModelLifecycleAction(
      uri: _llamaCppModelLoadUri(),
      modelId: modelId,
      actionLabel: 'load',
      modelIdField: 'model',
    );
  }

  Future<LocalModelLifecycleActionResult> unloadLlamaCppModel(String modelId) {
    return _postManagedModelLifecycleAction(
      uri: _llamaCppModelUnloadUri(),
      modelId: modelId,
      actionLabel: 'unload',
      modelIdField: 'model',
    );
  }

  Future<LocalModelLifecycleActionResult> loadLmStudioModel(String modelId) {
    return _postManagedModelLifecycleAction(
      uri: _lmStudioModelLoadUri(),
      modelId: modelId,
      actionLabel: 'load',
      modelIdField: 'model',
    );
  }

  Future<LocalModelLifecycleActionResult> unloadLmStudioModel(String modelId) {
    return _postManagedModelLifecycleAction(
      uri: _lmStudioModelUnloadUri(),
      modelId: modelId,
      actionLabel: 'unload',
      modelIdField: 'instance_id',
    );
  }

  Future<LocalModelLifecycleActionResult> loadOllamaModel(String modelId) {
    return _postOllamaLifecycleAction(
      uri: _ollamaGenerateUri(),
      modelId: modelId,
      actionLabel: 'load',
      bodyForModel: (model) => <String, Object>{
        'model': model,
        'prompt': '',
        'stream': false,
      },
    );
  }

  Future<LocalModelLifecycleActionResult> unloadOllamaModel(String modelId) {
    return _postOllamaLifecycleAction(
      uri: _ollamaGenerateUri(),
      modelId: modelId,
      actionLabel: 'unload',
      bodyForModel: (model) => <String, Object>{
        'model': model,
        'prompt': '',
        'stream': false,
        'keep_alive': 0,
      },
    );
  }

  Future<LocalModelLifecycleActionResult> pullOllamaModel(String modelId) {
    return _postOllamaLifecycleAction(
      uri: _ollamaPullUri(),
      modelId: modelId,
      actionLabel: 'pull',
      bodyForModel: (model) => <String, Object>{
        'model': model,
        'stream': false,
      },
    );
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

  Uri _lmStudioModelLoadUri() {
    return _nativeUri('/api/v1/models/load');
  }

  Uri _lmStudioModelUnloadUri() {
    return _nativeUri('/api/v1/models/unload');
  }

  Uri _ollamaTagsUri() {
    return _nativeUri('/api/tags');
  }

  Uri _ollamaPsUri() {
    return _nativeUri('/api/ps');
  }

  Uri _ollamaShowUri() {
    return _nativeUri('/api/show');
  }

  Uri _ollamaGenerateUri() {
    return _nativeUri('/api/generate');
  }

  Uri _ollamaPullUri() {
    return _nativeUri('/api/pull');
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

  Uri _llamaCppRouterModelsUri({required bool refresh}) {
    return _nativeUri(
      '/models',
      queryParameters: refresh ? const <String, String>{'reload': '1'} : null,
    );
  }

  Uri _llamaCppModelLoadUri() {
    return _nativeUri('/models/load');
  }

  Uri _llamaCppModelUnloadUri() {
    return _nativeUri('/models/unload');
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
    if (normalized.endsWith('/api')) {
      return normalized.substring(0, normalized.length - '/api'.length);
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

  Map<String, String> _jsonHeaders() {
    return {..._headers(), 'Content-Type': 'application/json'};
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

  Future<Object?> _tryPostJson(Uri uri, {required Object body}) async {
    try {
      final response = await _client
          .post(uri, headers: _jsonHeaders(), body: jsonEncode(body))
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

  Future<Map<String, Map<String, dynamic>>> _fetchOllamaShowDetailsByModel(
    Iterable<String> modelIds,
  ) async {
    final detailsByModel = <String, Map<String, dynamic>>{};
    for (final modelId in modelIds) {
      final decoded = await _tryPostJson(
        _ollamaShowUri(),
        body: <String, Object>{'model': modelId},
      );
      if (decoded is Map<String, dynamic>) {
        detailsByModel[modelId] = decoded;
      }
    }
    return detailsByModel;
  }

  Future<LocalModelLifecycleActionResult> _postManagedModelLifecycleAction({
    required Uri uri,
    required String modelId,
    required String actionLabel,
    required String modelIdField,
  }) async {
    final normalizedModelId = _normalizeModelId(modelId);
    if (normalizedModelId == null) {
      final result = LocalModelLifecycleActionResult.failure(
        message: 'A model id is required to $actionLabel a managed model.',
      );
      _logLifecycleActionResult(
        actionLabel: actionLabel,
        modelId: modelId,
        uri: uri,
        result: result,
      );
      return result;
    }

    _logLifecycleActionRequest(
      actionLabel: actionLabel,
      modelId: normalizedModelId,
      uri: uri,
      payloadLabel: modelIdField,
    );

    LocalModelLifecycleActionResult finish(
      LocalModelLifecycleActionResult result,
    ) {
      _logLifecycleActionResult(
        actionLabel: actionLabel,
        modelId: normalizedModelId,
        uri: uri,
        result: result,
      );
      return result;
    }

    try {
      final response = await _client
          .post(
            uri,
            headers: _jsonHeaders(),
            body: jsonEncode(<String, String>{modelIdField: normalizedModelId}),
          )
          .timeout(_nativeMetadataTimeout);
      if (_isLifecycleUnsupportedStatus(response.statusCode)) {
        return finish(
          LocalModelLifecycleActionResult.unsupported(
            message: _modelLifecycleUnsupportedMessage,
            statusCode: response.statusCode,
          ),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return finish(
          LocalModelLifecycleActionResult.failure(
            message: _readHttpErrorMessage(
              response.body,
              fallback:
                  'Failed to $actionLabel "$normalizedModelId" '
                  '(${response.statusCode}).',
            ),
            statusCode: response.statusCode,
          ),
        );
      }

      if (response.body.trim().isEmpty) {
        return finish(
          LocalModelLifecycleActionResult.success(
            message: 'Requested $actionLabel for "$normalizedModelId".',
          ),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['success'] == false) {
        return finish(
          LocalModelLifecycleActionResult.failure(
            message: _readHttpErrorMessage(
              response.body,
              fallback: 'Failed to $actionLabel "$normalizedModelId".',
            ),
            statusCode: response.statusCode,
          ),
        );
      }
      return finish(
        LocalModelLifecycleActionResult.success(
          message: 'Requested $actionLabel for "$normalizedModelId".',
        ),
      );
    } on FormatException catch (error) {
      _logLifecycleActionException(
        actionLabel: actionLabel,
        modelId: normalizedModelId,
        uri: uri,
        error: error,
      );
      return finish(
        LocalModelLifecycleActionResult.failure(
          message: 'Managed model $actionLabel response was not valid JSON.',
        ),
      );
    } on TimeoutException {
      return finish(
        LocalModelLifecycleActionResult.failure(
          message: 'Timed out while requesting $actionLabel for "$modelId".',
        ),
      );
    } on Object catch (error) {
      _logLifecycleActionException(
        actionLabel: actionLabel,
        modelId: normalizedModelId,
        uri: uri,
        error: error,
      );
      return finish(
        LocalModelLifecycleActionResult.unsupported(
          message: _modelLifecycleUnsupportedMessage,
        ),
      );
    }
  }

  Future<LocalModelLifecycleActionResult> _postOllamaLifecycleAction({
    required Uri uri,
    required String modelId,
    required String actionLabel,
    required Map<String, Object> Function(String modelId) bodyForModel,
  }) async {
    final normalizedModelId = _normalizeModelId(modelId);
    if (normalizedModelId == null) {
      final result = LocalModelLifecycleActionResult.failure(
        message: 'A model id is required to $actionLabel an Ollama model.',
      );
      _logLifecycleActionResult(
        actionLabel: actionLabel,
        modelId: modelId,
        uri: uri,
        result: result,
      );
      return result;
    }

    _logLifecycleActionRequest(
      actionLabel: actionLabel,
      modelId: normalizedModelId,
      uri: uri,
      payloadLabel: 'ollama',
    );

    LocalModelLifecycleActionResult finish(
      LocalModelLifecycleActionResult result,
    ) {
      _logLifecycleActionResult(
        actionLabel: actionLabel,
        modelId: normalizedModelId,
        uri: uri,
        result: result,
      );
      return result;
    }

    try {
      final response = await _client
          .post(
            uri,
            headers: _jsonHeaders(),
            body: jsonEncode(bodyForModel(normalizedModelId)),
          )
          .timeout(_nativeMetadataTimeout);
      if (_isLifecycleUnsupportedStatus(response.statusCode)) {
        return finish(
          LocalModelLifecycleActionResult.unsupported(
            message: _modelLifecycleUnsupportedMessage,
            statusCode: response.statusCode,
          ),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return finish(
          LocalModelLifecycleActionResult.failure(
            message: _readHttpErrorMessage(
              response.body,
              fallback:
                  'Failed to $actionLabel "$normalizedModelId" '
                  '(${response.statusCode}).',
            ),
            statusCode: response.statusCode,
          ),
        );
      }

      if (response.body.trim().isEmpty) {
        return finish(
          LocalModelLifecycleActionResult.success(
            message: 'Requested $actionLabel for "$normalizedModelId".',
          ),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
        return finish(
          LocalModelLifecycleActionResult.failure(
            message: _readHttpErrorMessage(
              response.body,
              fallback: 'Failed to $actionLabel "$normalizedModelId".',
            ),
            statusCode: response.statusCode,
          ),
        );
      }
      return finish(
        LocalModelLifecycleActionResult.success(
          message: 'Requested $actionLabel for "$normalizedModelId".',
        ),
      );
    } on FormatException catch (error) {
      _logLifecycleActionException(
        actionLabel: actionLabel,
        modelId: normalizedModelId,
        uri: uri,
        error: error,
      );
      return finish(
        LocalModelLifecycleActionResult.failure(
          message: 'Ollama model $actionLabel response was not valid JSON.',
        ),
      );
    } on TimeoutException {
      return finish(
        LocalModelLifecycleActionResult.failure(
          message: 'Timed out while requesting $actionLabel for "$modelId".',
        ),
      );
    } on Object catch (error) {
      _logLifecycleActionException(
        actionLabel: actionLabel,
        modelId: normalizedModelId,
        uri: uri,
        error: error,
      );
      return finish(
        LocalModelLifecycleActionResult.unsupported(
          message: _modelLifecycleUnsupportedMessage,
        ),
      );
    }
  }

  void _logLifecycleActionRequest({
    required String actionLabel,
    required String modelId,
    required Uri uri,
    required String payloadLabel,
  }) {
    appLog(
      '[LL9] Model lifecycle $actionLabel request: '
      'model="$modelId", uri=$uri, payload=$payloadLabel',
    );
  }

  void _logLifecycleActionResult({
    required String actionLabel,
    required String modelId,
    required Uri uri,
    required LocalModelLifecycleActionResult result,
  }) {
    final statusCode = result.statusCode == null
        ? ''
        : ', statusCode=${result.statusCode}';
    appLog(
      '[LL9] Model lifecycle $actionLabel result: '
      'model="$modelId", uri=$uri, '
      'supported=${result.supported}, succeeded=${result.succeeded}'
      '$statusCode, message=${result.message}',
    );
  }

  void _logLifecycleActionException({
    required String actionLabel,
    required String modelId,
    required Uri uri,
    required Object error,
  }) {
    appLog(
      '[LL9] Model lifecycle $actionLabel exception: '
      'model="$modelId", uri=$uri, error=${error.runtimeType}: $error',
    );
  }

  bool _canUseNvidiaNimFallback(Object? primaryError) {
    if (!ApiConstants.isNvidiaNimCloudBaseUrl(_baseUrl)) {
      return false;
    }
    if (!_hasConfiguredApiKey) {
      return false;
    }
    if (primaryError == null) {
      return true;
    }
    return primaryError is ModelCatalogHttpException &&
        (primaryError.statusCode == 404 || primaryError.statusCode == 405);
  }

  bool get _hasConfiguredApiKey {
    final normalized = _apiKey.trim();
    return normalized.isNotEmpty && normalized != ApiConstants.defaultApiKey;
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

  static _LifecycleStatus _readLifecycleStatus(Object? rawStatus) {
    if (rawStatus is String) {
      return _LifecycleStatus(value: rawStatus.trim());
    }
    if (rawStatus is! Map<String, dynamic>) {
      return const _LifecycleStatus(value: 'unknown');
    }

    final value = _readString(rawStatus, 'value')?.trim();
    final args = rawStatus['args'];
    return _LifecycleStatus(
      value: value == null || value.isEmpty ? 'unknown' : value,
      failed: rawStatus['failed'] == true,
      exitCode: _parsePositiveInt(rawStatus['exit_code']),
      commandArguments: args is List
          ? [
              for (final arg in args)
                if (arg is String) arg,
            ]
          : const [],
    );
  }

  static _LifecycleStatus? _readOpenAiLifecycleStatus(
    Map<String, dynamic> json,
  ) {
    final rawStatus =
        json['status'] ??
        json['state'] ??
        json['lifecycle_state'] ??
        json['lifecycleState'];
    if (rawStatus != null) {
      return _readLifecycleStatus(rawStatus);
    }

    final rawLoaded = json['loaded'] ?? json['is_loaded'] ?? json['isLoaded'];
    if (rawLoaded is bool) {
      return _LifecycleStatus(value: rawLoaded ? 'loaded' : 'unloaded');
    }
    return null;
  }

  static List<String> _lmStudioMetadataHints(Map<String, dynamic> json) {
    final hints = <String>[];

    void addHint(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        hints.add(value.trim());
      }
    }

    addHint(json['params_string']);
    addHint(json['selected_variant']);
    final quantization = json['quantization'];
    if (quantization is Map<String, dynamic>) {
      addHint(quantization['name']);
    }
    return hints;
  }

  static List<String> _ollamaModelIdsFromTags(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const [];
    }
    final models = json['models'];
    if (models is! List) {
      return const [];
    }
    final ids = <String>[];
    for (final item in models) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final id = _normalizeModelId(
        _readString(item, 'model') ?? _readString(item, 'name'),
      );
      if (id != null) {
        ids.add(id);
      }
    }
    return ids;
  }

  static Map<String, Map<String, dynamic>> _ollamaRunningModelsById(
    Object? json,
  ) {
    if (json is! Map<String, dynamic>) {
      return const {};
    }
    final models = json['models'];
    if (models is! List) {
      return const {};
    }

    final runningById = <String, Map<String, dynamic>>{};
    for (final item in models) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final id = _normalizeModelId(
        _readString(item, 'model') ?? _readString(item, 'name'),
      );
      if (id != null) {
        runningById[id] = item;
      }
    }
    return runningById;
  }

  static LocalManagedModel _ollamaManagedModel({
    required String id,
    required LocalModelLifecycleState state,
    required String statusValue,
    required List<Map<String, dynamic>> sources,
  }) {
    return LocalManagedModel(
      id: id,
      state: state,
      statusValue: statusValue,
      ownedBy: _ollamaOwnedBy(id),
      contextWindowTokens: _readFirstOllamaContextWindowTokens(sources),
      metadataHints: _ollamaMetadataHints(sources),
    );
  }

  static String? _ollamaOwnedBy(String modelId) {
    final slashIndex = modelId.indexOf('/');
    if (slashIndex <= 0) {
      return null;
    }
    return modelId.substring(0, slashIndex);
  }

  static int? _readFirstOllamaContextWindowTokens(
    List<Map<String, dynamic>> sources,
  ) {
    for (final source in sources) {
      final context = _readOllamaContextWindowTokens(source);
      if (context != null) {
        return context;
      }
    }
    return null;
  }

  static int? _readOllamaContextWindowTokens(Map<String, dynamic> json) {
    final direct = _readContextWindowTokens(json);
    if (direct != null) {
      return direct;
    }

    final modelInfo = json['model_info'];
    if (modelInfo is Map<String, dynamic>) {
      for (final entry in modelInfo.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'context_length' || key.endsWith('.context_length')) {
          final context = _parsePositiveInt(entry.value);
          if (context != null) {
            return context;
          }
        }
      }
    }

    final parameters = json['parameters'];
    if (parameters is String) {
      final match = RegExp(
        r'(^|\n)\s*num_ctx\s+(\d+)(\s|$)',
        multiLine: true,
      ).firstMatch(parameters);
      if (match != null) {
        return _parsePositiveInt(match.group(2));
      }
    }
    return null;
  }

  static List<String> _ollamaMetadataHints(List<Map<String, dynamic>> sources) {
    final hints = <String>[];

    void addHint(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        final normalized = value.trim();
        if (!hints.contains(normalized)) {
          hints.add(normalized);
        }
      }
    }

    void addSource(Map<String, dynamic> source) {
      addHint(source['parameters']);
      final details = source['details'];
      if (details is Map<String, dynamic>) {
        addHint(details['parameter_size']);
        addHint(details['quantization_level']);
        addHint(details['format']);
        addHint(details['family']);
        final families = details['families'];
        if (families is List) {
          for (final family in families) {
            addHint(family);
          }
        }
      }
    }

    for (final source in sources) {
      addSource(source);
    }
    return hints;
  }

  static bool _isLifecycleUnsupportedStatus(int statusCode) {
    return statusCode == 404 || statusCode == 405 || statusCode == 501;
  }

  static String _readHttpErrorMessage(String body, {required String fallback}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = _readString(error, 'message')?.trim();
          if (message != null && message.isNotEmpty) {
            return message;
          }
        } else if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
        final message = _readString(decoded, 'message')?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    } on Object {
      return fallback;
    }
    return fallback;
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

class _LifecycleStatus {
  const _LifecycleStatus({
    required this.value,
    this.failed = false,
    this.exitCode,
    this.commandArguments = const [],
  });

  final String value;
  final bool failed;
  final int? exitCode;
  final List<String> commandArguments;

  LocalModelLifecycleState get state {
    return switch (value.toLowerCase()) {
      'loaded' => LocalModelLifecycleState.loaded,
      'loading' => LocalModelLifecycleState.loading,
      'unloaded' => LocalModelLifecycleState.unloaded,
      'sleeping' => LocalModelLifecycleState.sleeping,
      'downloading' => LocalModelLifecycleState.downloading,
      _ => LocalModelLifecycleState.unknown,
    };
  }
}
