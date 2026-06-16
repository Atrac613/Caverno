/// LL17 weakness mining (Self-Harness): a verifier-grounded failure signature.
///
/// The triple is the clustering key — the terminal cause of the failure, the
/// causal status the verifier reported, and the abstract agent mechanism that
/// produced it. Traces sharing a signature form one weakness cluster.
class FailureSignature {
  const FailureSignature({
    required this.terminalCause,
    required this.causalStatus,
    required this.mechanism,
  });

  final String terminalCause;
  final String causalStatus;
  final String mechanism;

  @override
  bool operator ==(Object other) =>
      other is FailureSignature &&
      other.terminalCause == terminalCause &&
      other.causalStatus == causalStatus &&
      other.mechanism == mechanism;

  @override
  int get hashCode => Object.hash(terminalCause, causalStatus, mechanism);

  @override
  String toString() => '$terminalCause/$causalStatus/$mechanism';
}

/// One recorded failure: which case/session produced it, its signature, and a
/// short representative symptom.
class FailureTrace {
  const FailureTrace({
    required this.caseId,
    required this.signature,
    this.symptom = '',
  });

  final String caseId;
  final FailureSignature signature;
  final String symptom;
}

/// A weakness cluster: all traces sharing one signature, plus the evidence
/// bundle the proposer (a later LL17 stage) consumes.
class FailureCluster {
  const FailureCluster({
    required this.signature,
    required this.traces,
    required this.actionability,
  });

  final FailureSignature signature;
  final List<FailureTrace> traces;

  /// Heuristic weight (>= 0) for how fixable this mechanism is, multiplied with
  /// support to rank clusters.
  final double actionability;

  /// Number of traces backing this cluster.
  int get support => traces.length;

  /// Ranking score: support x estimated actionability (Self-Harness ordering).
  double get score => support * actionability;

  /// Up to [limit] representative case ids (insertion order, de-duplicated).
  List<String> representativeCaseIds({int limit = 3}) {
    final seen = <String>{};
    final ids = <String>[];
    for (final trace in traces) {
      if (seen.add(trace.caseId)) {
        ids.add(trace.caseId);
        if (ids.length == limit) break;
      }
    }
    return ids;
  }

  /// Distinct non-empty symptoms across the cluster's traces.
  List<String> get sharedSymptoms {
    final seen = <String>{};
    final symptoms = <String>[];
    for (final trace in traces) {
      final symptom = trace.symptom.trim();
      if (symptom.isNotEmpty && seen.add(symptom)) {
        symptoms.add(symptom);
      }
    }
    return symptoms;
  }
}

/// LL17 weakness miner: clusters failure traces by their verifier-grounded
/// signature and ranks the clusters by support x actionability, so the
/// proposer can target the highest-leverage weakness first.
///
/// Pure: the trace extraction (parsing session logs / edit-apply outcomes) and
/// the candidate proposal are separate pieces; this only does the clustering
/// and ranking.
class FailureTraceMiner {
  const FailureTraceMiner({this.actionabilityByMechanism = const {}});

  /// Per-mechanism actionability weights; mechanisms not listed default to 1.0.
  final Map<String, double> actionabilityByMechanism;

  List<FailureCluster> mine(List<FailureTrace> traces) {
    final grouped = <FailureSignature, List<FailureTrace>>{};
    for (final trace in traces) {
      grouped.putIfAbsent(trace.signature, () => []).add(trace);
    }

    final clusters = grouped.entries
        .map(
          (entry) => FailureCluster(
            signature: entry.key,
            traces: List.unmodifiable(entry.value),
            actionability: actionabilityByMechanism[entry.key.mechanism] ?? 1.0,
          ),
        )
        .toList();

    clusters.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final bySupport = b.support.compareTo(a.support);
      if (bySupport != 0) return bySupport;
      // Stable, deterministic tiebreak on the signature string.
      return a.signature.toString().compareTo(b.signature.toString());
    });

    return clusters;
  }
}
