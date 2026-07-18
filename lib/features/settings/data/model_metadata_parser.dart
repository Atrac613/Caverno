final class ModelMetadataParser {
  ModelMetadataParser._();

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

  static String? normalizeModelId(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static int? readContextWindowTokens(Map<String, dynamic> json) {
    for (final source in _metadataSources(json)) {
      for (final key in _contextWindowKeys) {
        final tokens = parsePositiveInt(source[key]);
        if (tokens != null) {
          return tokens;
        }
      }
    }
    return null;
  }

  static int? readSelectedLmStudioLoadedContext(
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
      final rawId = loadedInstance['id'];
      if (rawId is! String || rawId.trim() != selectedModelId) {
        continue;
      }
      final context = readContextWindowTokens(loadedInstance);
      if (context != null) {
        return context;
      }
    }
    return null;
  }

  static int? readFirstLmStudioLoadedContext(Object? loadedInstances) {
    if (loadedInstances is! List) {
      return null;
    }

    for (final loadedInstance in loadedInstances) {
      if (loadedInstance is! Map<String, dynamic>) {
        continue;
      }
      final context = readContextWindowTokens(loadedInstance);
      if (context != null) {
        return context;
      }
    }
    return null;
  }

  static int? parsePositiveInt(Object? value) {
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
}
