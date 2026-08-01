import 'dart:collection';

import '../../features/chat/domain/entities/chat_turn_owner.dart';
import 'data_source_classifier.dart';

/// Immutable owner-scoped taint evidence used by policy and audit readers.
final class ConversationTaintSnapshot {
  ConversationTaintSnapshot(Iterable<TrustLevel> trustLevels)
    : influencingTrustLevels = Set<TrustLevel>.unmodifiable(
        LinkedHashSet<TrustLevel>.of(trustLevels),
      );

  final Set<TrustLevel> influencingTrustLevels;

  bool get hasUntrustedInfluence =>
      influencingTrustLevels.contains(TrustLevel.untrusted);
}

/// Accumulates ordered trust evidence independently for each chat turn owner.
///
/// The propagation model is deliberately conservative: any untrusted evidence
/// recorded for an owner may influence that owner's next tool call. The state
/// computes advisory evidence only; approval policy remains responsible for
/// gating execution.
class ConversationTaintState {
  ConversationTaintState({
    DataSourceClassifier classifier = const DataSourceClassifier(),
  }) : _classifier = classifier;

  final DataSourceClassifier _classifier;
  final Map<ChatTurnOwner, LinkedHashSet<TrustLevel>> _trustLevelsByOwner = {};
  final Set<ChatTurnOwner> _retiredOwners = {};
  bool _disposed = false;

  /// Classifies and records a tool result for the exact owner.
  void recordToolResult({
    required ChatTurnOwner owner,
    required String toolName,
    bool isMcpTool = false,
  }) {
    final source = _classifier.classifyToolResultSource(
      toolName,
      isMcpTool: isMcpTool,
    );
    recordTrust(owner: owner, trust: _classifier.trustLevelOf(source));
  }

  /// Records already-classified evidence for the exact owner.
  void recordTrust({required ChatTurnOwner owner, required TrustLevel trust}) {
    if (_disposed || _retiredOwners.contains(owner)) return;
    _trustLevelsByOwner
        .putIfAbsent(owner, LinkedHashSet<TrustLevel>.new)
        .add(trust);
  }

  /// Returns an immutable, insertion-ordered snapshot for the exact owner.
  ConversationTaintSnapshot snapshot({required ChatTurnOwner owner}) {
    return ConversationTaintSnapshot(
      _trustLevelsByOwner[owner] ?? const <TrustLevel>{},
    );
  }

  Set<TrustLevel> influencingTrustLevels({required ChatTurnOwner owner}) =>
      snapshot(owner: owner).influencingTrustLevels;

  bool hasUntrustedInfluence({required ChatTurnOwner owner}) =>
      snapshot(owner: owner).hasUntrustedInfluence;

  /// Permanently retires the owner before removing its accumulated evidence.
  void clearOwner({required ChatTurnOwner owner}) {
    _retiredOwners.add(owner);
    _trustLevelsByOwner.remove(owner);
  }

  /// Permanently rejects future records and releases all retained owner data.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _trustLevelsByOwner.clear();
    _retiredOwners.clear();
  }
}
