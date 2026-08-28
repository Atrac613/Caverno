/// RAG2 generation-store envelope hosted by [AppDatabase] schema version 5.
///
/// This is not the Drift `schemaVersion`. Unknown envelope versions fail closed
/// without rewriting LL5 embedding rows.
const rag2DriftAdditiveSchemaContract =
    'rag2-drift-additive-schema-contract-v1';
const rag2DriftStoreSchema = 'caverno_rag2_drift_generation_store';
const rag2DriftStoreSchemaVersion = 1;

/// Thrown when `AppDatabase` cannot host the RAG2 v1 envelope.
///
/// Missing metadata on a file that already has `rag2_generations` is not an
/// empty store. The migration must not create or seed tables in that case.
final class Rag2DriftSchemaException implements Exception {
  const Rag2DriftSchemaException(this.reason);

  final String reason;

  @override
  String toString() => 'RAG2 Drift schema failed: $reason';
}
