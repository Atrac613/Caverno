/// Where a resolved context window came from, so a number taken from bundled
/// vendor documentation is never mistaken for one the serving stack reported.
enum ModelContextWindowSource {
  /// Reported by the endpoint itself (llama.cpp `n_ctx`, LM Studio loaded
  /// context, Ollama `num_ctx`, or a gateway that fills `context_length`).
  endpoint,

  /// Taken from the bundled published-spec table because the endpoint was
  /// silent, as OpenAI's `/v1/models` always is.
  publishedSpec,
}

class ModelCatalogEntry {
  const ModelCatalogEntry({
    required this.id,
    this.ownedBy,
    this.contextWindowTokens,
    this.contextWindowSource = ModelContextWindowSource.endpoint,
  });

  final String id;
  final String? ownedBy;
  final int? contextWindowTokens;

  /// Provenance of [contextWindowTokens]. Meaningless when that is null.
  final ModelContextWindowSource contextWindowSource;

  ModelCatalogEntry copyWith({
    String? id,
    String? ownedBy,
    int? contextWindowTokens,
    ModelContextWindowSource? contextWindowSource,
  }) {
    return ModelCatalogEntry(
      id: id ?? this.id,
      ownedBy: ownedBy ?? this.ownedBy,
      contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
      contextWindowSource: contextWindowSource ?? this.contextWindowSource,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ModelCatalogEntry &&
            id == other.id &&
            ownedBy == other.ownedBy &&
            contextWindowTokens == other.contextWindowTokens &&
            contextWindowSource == other.contextWindowSource;
  }

  @override
  int get hashCode =>
      Object.hash(id, ownedBy, contextWindowTokens, contextWindowSource);

  @override
  String toString() {
    return 'ModelCatalogEntry(id: $id, ownedBy: $ownedBy, '
        'contextWindowTokens: $contextWindowTokens, '
        'contextWindowSource: ${contextWindowSource.name})';
  }
}
