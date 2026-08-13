import '../entities/ll37_objective_verdict_record.dart';
import '../entities/ll37_objective_vote_identity.dart';
import 'll37_objective_verification_panel.dart';

enum Ll37ObjectiveVoteAggregateStatus { pending, converged, stalled, capped }

enum Ll37ObjectiveVoteAggregateOutcome {
  pending,
  notRefuted,
  refuted,
  unverifiable,
}

/// One independently measured verifier route in append-only vote-slot order.
class Ll37ObjectiveVoteRoute {
  const Ll37ObjectiveVoteRoute({
    required this.verifierProfileKey,
    required this.fidelityReportSha256,
  });

  final String verifierProfileKey;
  final String fidelityReportSha256;

  String get normalizedProfileKey => verifierProfileKey.trim();
  String get normalizedReportSha256 =>
      fidelityReportSha256.trim().toLowerCase();

  bool matches(Ll37ObjectiveVerdictRecord record) {
    return record.verifierProfileKey == normalizedProfileKey &&
        record.fidelityReportSha256.toLowerCase() == normalizedReportSha256;
  }

  String voteId({required String candidateId, required int voteIndex}) {
    return Ll37ObjectiveVoteIdentity.build(
      candidateId: candidateId,
      verifierProfileKey: normalizedProfileKey,
      fidelityReportSha256: normalizedReportSha256,
      voteIndex: voteIndex,
    );
  }
}

class Ll37ObjectiveVoteAggregate {
  Ll37ObjectiveVoteAggregate({
    required this.candidateId,
    required List<Ll37ObjectiveVoteRoute> routes,
    required List<Ll37ObjectiveVerdictRecord> votes,
    required this.status,
    required this.outcome,
    required this.blocking,
    required this.detail,
  }) : routes = List.unmodifiable(routes),
       votes = List.unmodifiable(votes);

  final String candidateId;
  final List<Ll37ObjectiveVoteRoute> routes;
  final List<Ll37ObjectiveVerdictRecord> votes;
  final Ll37ObjectiveVoteAggregateStatus status;
  final Ll37ObjectiveVoteAggregateOutcome outcome;
  final Ll37ObjectiveBlocking? blocking;
  final String detail;

  int get voteCount => votes.length;
  int get maxVoteCount => routes.length;
  bool get isTerminal => status != Ll37ObjectiveVoteAggregateStatus.pending;
}

class Ll37ObjectiveVotePlan {
  const Ll37ObjectiveVotePlan({
    required this.aggregate,
    required this.nextVoteId,
    required this.nextVoteIndex,
    required this.nextRoute,
  });

  final Ll37ObjectiveVoteAggregate aggregate;
  final String? nextVoteId;
  final int? nextVoteIndex;
  final Ll37ObjectiveVoteRoute? nextRoute;

  bool get shouldRequest =>
      !aggregate.isTerminal &&
      nextVoteId != null &&
      nextVoteIndex != null &&
      nextRoute != null;
}

/// Deterministic cap and aggregation policy across distinct measured routes.
class Ll37ObjectiveVotePolicy {
  const Ll37ObjectiveVotePolicy();

  static const majorityCount = 2;

  Ll37ObjectiveVotePlan plan({
    required String candidateId,
    required Iterable<Ll37ObjectiveVoteRoute> routes,
    required Iterable<Ll37ObjectiveVerdictRecord> history,
  }) {
    final normalizedCandidateId = candidateId.trim();
    if (normalizedCandidateId.isEmpty) {
      throw const FormatException('candidateId must be a non-empty string');
    }
    final boundedRoutes = _boundedRoutes(routes);
    final votes = _validCohort(
      candidateId: normalizedCandidateId,
      routes: boundedRoutes,
      history: history,
    );
    final aggregate = _aggregate(
      candidateId: normalizedCandidateId,
      routes: boundedRoutes,
      votes: votes,
    );
    if (aggregate.isTerminal) {
      return Ll37ObjectiveVotePlan(
        aggregate: aggregate,
        nextVoteId: null,
        nextVoteIndex: null,
        nextRoute: null,
      );
    }
    final occupied = votes.map((vote) => vote.voteIndex).toSet();
    int? nextVoteIndex;
    for (var index = 1; index <= boundedRoutes.length; index++) {
      if (!occupied.contains(index)) {
        nextVoteIndex = index;
        break;
      }
    }
    final nextRoute = nextVoteIndex == null
        ? null
        : boundedRoutes[nextVoteIndex - 1];
    return Ll37ObjectiveVotePlan(
      aggregate: aggregate,
      nextVoteId: nextRoute?.voteId(
        candidateId: normalizedCandidateId,
        voteIndex: nextVoteIndex!,
      ),
      nextVoteIndex: nextVoteIndex,
      nextRoute: nextRoute,
    );
  }

  List<Ll37ObjectiveVoteRoute> _boundedRoutes(
    Iterable<Ll37ObjectiveVoteRoute> routes,
  ) {
    final normalized = <Ll37ObjectiveVoteRoute>[];
    final identities = <String>{};
    for (final route in routes) {
      final profileKey = route.normalizedProfileKey;
      final reportSha = route.normalizedReportSha256;
      if (profileKey.isEmpty || reportSha.isEmpty) {
        throw const FormatException(
          'verifier route identity fields must be non-empty',
        );
      }
      final identity = '$profileKey\u0000$reportSha';
      if (!identities.add(identity)) {
        throw const FormatException('verifier routes must be distinct');
      }
      normalized.add(
        Ll37ObjectiveVoteRoute(
          verifierProfileKey: profileKey,
          fidelityReportSha256: reportSha,
        ),
      );
      if (normalized.length == Ll37ObjectiveVoteIdentity.maxVotesPerCandidate) {
        break;
      }
    }
    if (normalized.isEmpty) {
      throw const FormatException('at least one verifier route is required');
    }
    return normalized;
  }

  List<Ll37ObjectiveVerdictRecord> _validCohort({
    required String candidateId,
    required List<Ll37ObjectiveVoteRoute> routes,
    required Iterable<Ll37ObjectiveVerdictRecord> history,
  }) {
    final byVoteIndex = <int, Ll37ObjectiveVerdictRecord>{};
    for (final record in history) {
      if (record.candidateId != candidateId ||
          record.voteIndex < 1 ||
          record.voteIndex > routes.length) {
        continue;
      }
      final route = routes[record.voteIndex - 1];
      if (!route.matches(record)) continue;
      final expectedVoteId = route.voteId(
        candidateId: candidateId,
        voteIndex: record.voteIndex,
      );
      if (record.voteId != expectedVoteId) continue;
      final previous = byVoteIndex[record.voteIndex];
      if (previous == null || record.recordedAt.isAfter(previous.recordedAt)) {
        byVoteIndex[record.voteIndex] = record;
      }
    }
    return byVoteIndex.values.toList(growable: false)
      ..sort((left, right) => left.voteIndex.compareTo(right.voteIndex));
  }

  Ll37ObjectiveVoteAggregate _aggregate({
    required String candidateId,
    required List<Ll37ObjectiveVoteRoute> routes,
    required List<Ll37ObjectiveVerdictRecord> votes,
  }) {
    if (_hasRepeatedUnverifiableGap(votes)) {
      return _result(
        candidateId: candidateId,
        routes: routes,
        votes: votes,
        status: Ll37ObjectiveVoteAggregateStatus.stalled,
        outcome: Ll37ObjectiveVoteAggregateOutcome.unverifiable,
        blocking: Ll37ObjectiveBlocking.unverifiable,
        detail: 'identical unverifiable evidence repeated twice',
      );
    }
    for (final classification in const [
      Ll37ObjectiveBlocking.contradiction,
      Ll37ObjectiveBlocking.none,
      Ll37ObjectiveBlocking.unverifiable,
    ]) {
      final count = votes
          .where((vote) => vote.blocking == classification.name)
          .length;
      if (count >= majorityCount) {
        return _result(
          candidateId: candidateId,
          routes: routes,
          votes: votes,
          status: Ll37ObjectiveVoteAggregateStatus.converged,
          outcome: switch (classification) {
            Ll37ObjectiveBlocking.contradiction =>
              Ll37ObjectiveVoteAggregateOutcome.refuted,
            Ll37ObjectiveBlocking.none =>
              Ll37ObjectiveVoteAggregateOutcome.notRefuted,
            Ll37ObjectiveBlocking.unverifiable =>
              Ll37ObjectiveVoteAggregateOutcome.unverifiable,
          },
          blocking: classification,
          detail: 'two votes agree on ${classification.name}',
        );
      }
    }
    if (votes.length >= routes.length) {
      return _result(
        candidateId: candidateId,
        routes: routes,
        votes: votes,
        status: Ll37ObjectiveVoteAggregateStatus.capped,
        outcome: Ll37ObjectiveVoteAggregateOutcome.unverifiable,
        blocking: Ll37ObjectiveBlocking.unverifiable,
        detail: 'route vote cap reached without a majority',
      );
    }
    return _result(
      candidateId: candidateId,
      routes: routes,
      votes: votes,
      status: Ll37ObjectiveVoteAggregateStatus.pending,
      outcome: Ll37ObjectiveVoteAggregateOutcome.pending,
      blocking: null,
      detail: votes.isEmpty
          ? 'no votes recorded'
          : 'another bounded vote is required',
    );
  }

  Ll37ObjectiveVoteAggregate _result({
    required String candidateId,
    required List<Ll37ObjectiveVoteRoute> routes,
    required List<Ll37ObjectiveVerdictRecord> votes,
    required Ll37ObjectiveVoteAggregateStatus status,
    required Ll37ObjectiveVoteAggregateOutcome outcome,
    required Ll37ObjectiveBlocking? blocking,
    required String detail,
  }) {
    return Ll37ObjectiveVoteAggregate(
      candidateId: candidateId,
      routes: routes,
      votes: votes,
      status: status,
      outcome: outcome,
      blocking: blocking,
      detail: detail,
    );
  }

  bool _hasRepeatedUnverifiableGap(List<Ll37ObjectiveVerdictRecord> votes) {
    if (votes.length < 2) return false;
    final previous = votes[votes.length - 2];
    final latest = votes.last;
    if (previous.blocking != Ll37ObjectiveBlocking.unverifiable.name ||
        latest.blocking != Ll37ObjectiveBlocking.unverifiable.name) {
      return false;
    }
    final previousGap = _gapFingerprint(previous);
    return previousGap.isNotEmpty && previousGap == _gapFingerprint(latest);
  }

  String _gapFingerprint(Ll37ObjectiveVerdictRecord record) {
    final parts = <String>[
      if (record.error?.trim().isNotEmpty ?? false) record.error!.trim(),
      ...record.findings.map(
        (finding) => '${finding.kind}|${finding.location}|${finding.detail}',
      ),
    ].map(_normalize).where((part) => part.isNotEmpty).toList()..sort();
    return parts.join('\n');
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
