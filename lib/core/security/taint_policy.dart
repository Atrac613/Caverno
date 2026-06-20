import 'data_source_classifier.dart';
import 'tool_capability_classifier.dart';

/// SEC2 (Taint-Aware Tool Execution), slice 1: a pure policy that decides how to
/// treat a proposed tool call when untrusted (or lower-trust) evidence
/// influenced it.
///
/// Builds directly on SEC1: a tool's [ToolCapability] and the [TrustLevel]s of
/// the evidence that influenced the call. Pure and advisory — it returns a
/// recommendation; honoring it (a mandatory non-cacheable approval, or a block)
/// is the caller's job in a later wiring slice, so this cannot weaken any
/// existing default on its own.
enum TaintDecision {
  /// Run as usual: nothing untrusted influenced the call, or the action is
  /// read-only/inert and safe to proceed even with untrusted influence.
  allow,

  /// Escalate to an explicit, non-cacheable approval before running, because
  /// untrusted evidence influenced a state-changing or network action.
  requireApproval,

  /// Refuse to auto-run: a high-risk, state-mutating action driven by untrusted
  /// content (the network-fetch-then-execute / AMOS malware-vector shape). The
  /// user must re-issue it themselves.
  block,
}

/// Pure SEC2 taint policy. Stateless and side-effect free.
class TaintPolicy {
  const TaintPolicy();

  /// Decide how to treat [capability] given the trust levels of the evidence
  /// in [influencingTrustLevels] that influenced the call.
  ///
  /// - No untrusted influence -> [TaintDecision.allow].
  /// - Untrusted influence on a read-only/inert action -> [TaintDecision.allow]
  ///   (safe reads proceed; SEC2 acceptance).
  /// - Untrusted influence on a high-risk, state-mutating action ->
  ///   [TaintDecision.block] (untrusted content must not drive shell/SSH/git/
  ///   remote/computer-use execution).
  /// - Untrusted influence on any other state-changing or network action ->
  ///   [TaintDecision.requireApproval] (write/network actions escalate).
  TaintDecision assess({
    required ToolCapability capability,
    required Set<TrustLevel> influencingTrustLevels,
  }) {
    final tainted = influencingTrustLevels.contains(TrustLevel.untrusted);
    if (!tainted) {
      return TaintDecision.allow;
    }
    // Safe read-only / inert actions proceed even when untrusted content is in
    // play: they cannot, by themselves, change the host or exfiltrate.
    if (!capability.mutatesState && !capability.accessesNetwork) {
      return TaintDecision.allow;
    }
    if (capability.riskTier == ToolRiskTier.high && capability.mutatesState) {
      return TaintDecision.block;
    }
    return TaintDecision.requireApproval;
  }
}
