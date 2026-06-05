class ModelCatalogEntry {
  const ModelCatalogEntry({
    required this.id,
    this.ownedBy,
    this.contextWindowTokens,
  });

  final String id;
  final String? ownedBy;
  final int? contextWindowTokens;

  ModelCatalogEntry copyWith({
    String? id,
    String? ownedBy,
    int? contextWindowTokens,
  }) {
    return ModelCatalogEntry(
      id: id ?? this.id,
      ownedBy: ownedBy ?? this.ownedBy,
      contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ModelCatalogEntry &&
            id == other.id &&
            ownedBy == other.ownedBy &&
            contextWindowTokens == other.contextWindowTokens;
  }

  @override
  int get hashCode => Object.hash(id, ownedBy, contextWindowTokens);

  @override
  String toString() {
    return 'ModelCatalogEntry(id: $id, ownedBy: $ownedBy, '
        'contextWindowTokens: $contextWindowTokens)';
  }
}
