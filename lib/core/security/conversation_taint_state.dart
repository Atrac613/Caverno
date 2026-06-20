import 'data_source_classifier.dart';

/// SEC2 (Taint-Aware Tool Execution), slice 2: accumulates the trust levels of
/// the evidence that has entered the conversation this turn, so the approval
/// boundary can ask "did untrusted content influence this call?" via
/// [TaintPolicy].
///
/// This is a deliberately conservative propagation model: true data-flow taint
/// is hard, so any untrusted evidence present in the current turn is treated as
/// potentially influencing the next tool call. Pure and in-memory; the tool
/// loop feeds it [recordToolResult] / [recordContent] and reads
/// [influencingTrustLevels]. It is advisory — it computes, it does not gate.
class ConversationTaintState {
  ConversationTaintState({
    DataSourceClassifier classifier = const DataSourceClassifier(),
  }) : _classifier = classifier;

  final DataSourceClassifier _classifier;
  final Set<TrustLevel> _trustLevels = <TrustLevel>{};

  /// Record a tool result by its producing tool, classifying its provenance and
  /// folding the resulting trust level into the accumulated set.
  void recordToolResult(String toolName, {bool isMcpTool = false}) {
    final source = _classifier.classifyToolResultSource(
      toolName,
      isMcpTool: isMcpTool,
    );
    _trustLevels.add(_classifier.trustLevelOf(source));
  }

  /// Record evidence whose trust level is already known (e.g. a user message,
  /// or an explicitly-classified document).
  void recordTrust(TrustLevel trust) => _trustLevels.add(trust);

  /// The trust levels of evidence accumulated this turn.
  Set<TrustLevel> get influencingTrustLevels =>
      Set<TrustLevel>.unmodifiable(_trustLevels);

  /// Whether any untrusted evidence has entered the conversation this turn.
  bool get hasUntrustedInfluence =>
      _trustLevels.contains(TrustLevel.untrusted);

  /// Clear the accumulated taint (e.g. at the start of a new turn).
  void reset() => _trustLevels.clear();
}
