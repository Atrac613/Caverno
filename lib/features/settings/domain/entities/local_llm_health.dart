/// Whether a registered local LLM answered when last asked.
enum LocalLlmReachability { online, offline }

/// How the model names in a [LocalLlmHealthSnapshot] were established.
enum LocalLlmModelEvidence {
  /// The server reported per-model lifecycle state and these are the ones it
  /// says are loaded (LM Studio instances, llama.cpp managed models, Ollama
  /// running models).
  loaded,

  /// The server exposes no lifecycle API, so these are the models it
  /// advertises on `/v1/models`. For a single-model llama.cpp process that is
  /// the loaded model; for a catalog-style server it may not be.
  advertised,

  /// Nothing to report: offline, or online with an empty catalog.
  none,
}

/// One registered local LLM endpoint as last observed.
///
/// Deliberately carries the evidence class alongside the names: "these models
/// are loaded" and "these models are offered" are different claims, and a panel
/// that renders them identically would invent the stronger one.
class LocalLlmHealthSnapshot {
  const LocalLlmHealthSnapshot({
    required this.endpointId,
    required this.label,
    required this.baseUrl,
    required this.isPrimary,
    required this.reachability,
    required this.modelEvidence,
    required this.modelIds,
    required this.checkedAt,
    this.detail,
  });

  const LocalLlmHealthSnapshot.offline({
    required this.endpointId,
    required this.label,
    required this.baseUrl,
    required this.isPrimary,
    required this.checkedAt,
    this.detail,
  }) : reachability = LocalLlmReachability.offline,
       modelEvidence = LocalLlmModelEvidence.none,
       modelIds = const <String>[];

  final String endpointId;
  final String label;
  final String baseUrl;
  final bool isPrimary;
  final LocalLlmReachability reachability;
  final LocalLlmModelEvidence modelEvidence;
  final List<String> modelIds;
  final DateTime checkedAt;

  /// One short line explaining a non-obvious state, or null. Carries the
  /// server's own words for a failure rather than a rephrasing.
  final String? detail;

  bool get isOnline => reachability == LocalLlmReachability.online;

  bool get hasModels => modelIds.isNotEmpty;
}
