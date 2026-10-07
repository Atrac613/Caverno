import '../domain/entities/model_catalog_entry.dart';

/// Merges complementary catalog metadata while preserving known values.
abstract final class ModelCatalogMerge {
  static void putPreferredEntry(
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

  static List<ModelCatalogEntry> sortedUnique(
    Iterable<ModelCatalogEntry> entries,
  ) {
    final entriesById = <String, ModelCatalogEntry>{};
    for (final entry in entries) {
      putPreferredEntry(entriesById, entry);
    }
    return entriesById.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }
}
