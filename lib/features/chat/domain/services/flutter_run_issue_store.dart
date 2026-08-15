import '../entities/flutter_run_issue.dart';

/// The issues found in one run, keyed by signature.
///
/// Holds the counting rule the whole design rests on -- a repeat bumps a
/// counter instead of becoming a second entry -- separately from the policy
/// that decides when to spend a model call on one.
class FlutterRunIssueStore {
  final issuesBySignature = <String, FlutterRunIssue>{};
  final pending = <String, FlutterRunLogCandidate>{};

  List<FlutterRunIssue> get issues =>
      List.unmodifiable(issuesBySignature.values);

  /// Counts a repeat, or lists a new candidate. True when either happened.
  ///
  /// Counting rather than re-listing is the whole point of the signature: a
  /// re-thrown exception must not become a second issue or a second call.
  bool merge(FlutterRunLogCandidate candidate) {
    final known = issuesBySignature[candidate.signature];
    if (known != null) {
      issuesBySignature[candidate.signature] = known.copyWith(
        occurrences: known.occurrences + 1,
      );
      return true;
    }
    if (pending.containsKey(candidate.signature)) return false;
    queue(candidate);
    return true;
  }

  /// Lists a candidate straight away, before any analysis: the block was a
  /// real failure the moment it was printed.
  void queue(FlutterRunLogCandidate candidate) {
    pending[candidate.signature] = candidate;
    issuesBySignature[candidate.signature] = FlutterRunIssue(
      signature: candidate.signature,
      kind: candidate.kind,
      title: candidate.headline,
      evidence: candidate.evidence,
      location: candidate.location,
    );
  }

  /// Stores an analysed issue, or drops it when the model ruled out a window
  /// it was allowed to rule out.
  void record(String signature, FlutterRunIssue analysed) {
    if (analysed.isDismissable && analysed.dismissed) {
      issuesBySignature.remove(signature);
      return;
    }
    // The count may have grown while the model was thinking.
    issuesBySignature[signature] = analysed.copyWith(
      occurrences:
          issuesBySignature[signature]?.occurrences ?? analysed.occurrences,
    );
  }

  void clear() {
    issuesBySignature.clear();
    pending.clear();
  }
}
