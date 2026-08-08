import '../domain/entities/model_catalog_entry.dart';

/// Context windows a vendor publishes for models whose endpoint advertises none.
///
/// OpenAI's `/v1/models` returns only `id`/`object`/`created`/`owned_by`, so a
/// cloud model has no queryable context budget — the number exists solely in the
/// vendor's documentation. This table is consulted only *after* every
/// endpoint-reported source comes back silent (llama.cpp `n_ctx`, LM Studio
/// loaded context, Ollama `num_ctx`), never instead of one, so a proxy serving a
/// model with a reduced window still wins.
///
/// Entries are keyed by model id rather than by provider, because the same id
/// reaches Caverno through gateways that rename the endpoint but not the model.
///
/// Verified against https://developers.openai.com/api/docs/models on
/// 2026-08-08. A vendor can change these numbers, and this table cannot notice:
/// values sourced from here are labelled `ModelContextWindowSource.publishedSpec`
/// so the UI can say where the budget came from instead of presenting it as
/// endpoint truth.
final class PublishedModelContextWindows {
  PublishedModelContextWindows._();

  static const _byModelId = <String, int>{
    // GPT-5.6 family — 1,050,000 context, 128,000 max output.
    'gpt-5.6-sol': 1050000,
    'gpt-5.6-terra': 1050000,
    'gpt-5.6-luna': 1050000,
  };

  /// Dated snapshot suffix (`-2026-08-01`) as OpenAI pins model versions.
  static final _snapshotDateSuffix = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Published context window for [modelId], or null when it is not listed.
  ///
  /// A dated snapshot inherits from its base id, so pinning
  /// `gpt-5.6-luna-2026-08-01` does not fall back to "unknown". Only a date
  /// suffix inherits — a differently named variant (`-mini`, `-pro`) is a
  /// different model and must be listed on its own.
  static int? lookup(String modelId) {
    final normalized = modelId.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    final exact = _byModelId[normalized];
    if (exact != null) {
      return exact;
    }

    for (final entry in _byModelId.entries) {
      final prefix = '${entry.key}-';
      if (!normalized.startsWith(prefix)) {
        continue;
      }
      if (_snapshotDateSuffix.hasMatch(normalized.substring(prefix.length))) {
        return entry.value;
      }
    }
    return null;
  }

  /// Fills in the published window for every [catalog] entry the endpoint left
  /// without one.
  ///
  /// Applied after the catalog is assembled, so an endpoint-reported window is
  /// never overwritten: a gateway serving a listed id with a reduced window
  /// still wins, and only a genuinely silent entry changes.
  static List<ModelCatalogEntry> fill(List<ModelCatalogEntry> catalog) {
    return [
      for (final entry in catalog)
        if (entry.contextWindowTokens != null)
          entry
        else
          switch (lookup(entry.id)) {
            final int tokens => entry.copyWith(
              contextWindowTokens: tokens,
              contextWindowSource: ModelContextWindowSource.publishedSpec,
            ),
            null => entry,
          },
    ];
  }
}
