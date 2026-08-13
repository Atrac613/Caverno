import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/ll37_objective_verdict_record.dart';
import 'll37_objective_verification_panel.dart';
import 'll37_objective_vote_policy.dart';

enum Ll37ObjectiveContinuationStatus {
  noAction,
  repairReview,
  userDecisionRequired,
}

class Ll37ObjectiveContinuationGap {
  const Ll37ObjectiveContinuationGap({
    required this.id,
    required this.kind,
    required this.location,
    required this.detail,
  });

  final String id;
  final String kind;
  final String location;
  final String detail;
}

class Ll37ObjectiveContinuationReview {
  Ll37ObjectiveContinuationReview({
    required this.status,
    required this.candidateId,
    required this.objective,
    required List<String> acceptanceCriteria,
    required List<Ll37ObjectiveContinuationGap> gaps,
    required this.detail,
    this.repairNudge,
  }) : acceptanceCriteria = List.unmodifiable(acceptanceCriteria),
       gaps = List.unmodifiable(gaps);

  final Ll37ObjectiveContinuationStatus status;
  final String candidateId;
  final String objective;
  final List<String> acceptanceCriteria;
  final List<Ll37ObjectiveContinuationGap> gaps;
  final String detail;
  final String? repairNudge;

  bool get canCopyRepairNudge =>
      status == Ll37ObjectiveContinuationStatus.repairReview &&
      (repairNudge?.isNotEmpty ?? false);
}

/// Builds the user-reviewed boundary between an LL37 verdict and repair work.
class Ll37ObjectiveContinuationPolicy {
  const Ll37ObjectiveContinuationPolicy();

  Ll37ObjectiveContinuationReview review(Ll37ObjectiveVoteAggregate aggregate) {
    final contract = _contract(aggregate);
    if (contract == null) {
      return Ll37ObjectiveContinuationReview(
        status: Ll37ObjectiveContinuationStatus.userDecisionRequired,
        candidateId: aggregate.candidateId,
        objective: '',
        acceptanceCriteria: const [],
        gaps: const [],
        detail: 'Verifier votes disagree on the frozen objective contract.',
      );
    }
    if (!aggregate.isTerminal) {
      return _result(
        aggregate: aggregate,
        contract: contract,
        status: Ll37ObjectiveContinuationStatus.noAction,
        detail: 'Verifier voting is still pending.',
      );
    }
    if (aggregate.outcome == Ll37ObjectiveVoteAggregateOutcome.notRefuted) {
      return _result(
        aggregate: aggregate,
        contract: contract,
        status: Ll37ObjectiveContinuationStatus.noAction,
        detail: 'The objective was not refuted.',
      );
    }
    if (aggregate.status != Ll37ObjectiveVoteAggregateStatus.converged ||
        aggregate.outcome != Ll37ObjectiveVoteAggregateOutcome.refuted ||
        aggregate.blocking != Ll37ObjectiveBlocking.contradiction) {
      return _result(
        aggregate: aggregate,
        contract: contract,
        status: Ll37ObjectiveContinuationStatus.userDecisionRequired,
        detail: 'The verifier result requires a user decision.',
      );
    }
    final gaps = _gaps(aggregate.votes);
    if (gaps.isEmpty) {
      return _result(
        aggregate: aggregate,
        contract: contract,
        status: Ll37ObjectiveContinuationStatus.userDecisionRequired,
        detail: 'The refutation has no concrete repair gap.',
      );
    }
    final nudge = _repairNudge(
      candidateId: aggregate.candidateId,
      objective: contract.objective,
      criteria: contract.criteria,
      gaps: gaps,
    );
    return Ll37ObjectiveContinuationReview(
      status: Ll37ObjectiveContinuationStatus.repairReview,
      candidateId: aggregate.candidateId,
      objective: contract.objective,
      acceptanceCriteria: contract.criteria,
      gaps: gaps,
      detail: 'Review the frozen repair scope before starting new work.',
      repairNudge: nudge,
    );
  }

  Ll37ObjectiveContinuationReview _result({
    required Ll37ObjectiveVoteAggregate aggregate,
    required _Ll37ObjectiveContract contract,
    required Ll37ObjectiveContinuationStatus status,
    required String detail,
  }) {
    return Ll37ObjectiveContinuationReview(
      status: status,
      candidateId: aggregate.candidateId,
      objective: contract.objective,
      acceptanceCriteria: contract.criteria,
      gaps: const [],
      detail: detail,
    );
  }

  _Ll37ObjectiveContract? _contract(Ll37ObjectiveVoteAggregate aggregate) {
    if (aggregate.votes.isEmpty) return null;
    final first = aggregate.votes.first;
    final objective = _normalizeContractText(first.objective);
    final criteria = first.acceptanceCriteria
        .map(_normalizeContractText)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (objective.isEmpty || criteria.isEmpty) return null;
    final fingerprint = _contractFingerprint(objective, criteria);
    for (final vote in aggregate.votes.skip(1)) {
      if (_contractFingerprint(vote.objective, vote.acceptanceCriteria) !=
          fingerprint) {
        return null;
      }
    }
    return _Ll37ObjectiveContract(objective: objective, criteria: criteria);
  }

  String _contractFingerprint(String objective, Iterable<String> criteria) {
    return jsonEncode({
      'objective': _normalizeContractText(objective),
      'criteria': criteria.map(_normalizeContractText).toList(growable: false),
    });
  }

  List<Ll37ObjectiveContinuationGap> _gaps(
    Iterable<Ll37ObjectiveVerdictRecord> votes,
  ) {
    final unique = <String, Ll37ObjectiveContinuationGap>{};
    for (final vote in votes) {
      if (vote.blocking != Ll37ObjectiveBlocking.contradiction.name) continue;
      for (final finding in vote.findings) {
        final kind = finding.kind.trim();
        final location = finding.location.trim();
        final detail = finding.detail.trim();
        if (kind.isEmpty || location.isEmpty || detail.isEmpty) continue;
        final canonical = jsonEncode({
          'kind': _normalize(kind),
          'location': _normalize(location),
          'detail': _normalize(detail),
        });
        final candidate = Ll37ObjectiveContinuationGap(
          id: 'll37-gap-${sha256.convert(utf8.encode(canonical)).toString().substring(0, 16)}',
          kind: _normalizeContractText(kind),
          location: _normalizeContractText(location),
          detail: _normalizeContractText(detail),
        );
        unique.update(
          canonical,
          (current) => _preferredGapDisplay(current, candidate),
          ifAbsent: () => candidate,
        );
      }
    }
    final gaps = unique.values.toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    return gaps;
  }

  String _repairNudge({
    required String candidateId,
    required String objective,
    required List<String> criteria,
    required List<Ll37ObjectiveContinuationGap> gaps,
  }) {
    final buffer = StringBuffer()
      ..writeln('Repair the reviewed LL37 objective gaps.')
      ..writeln()
      ..writeln('Candidate: $candidateId')
      ..writeln('Frozen objective: $objective')
      ..writeln('Frozen acceptance criteria:');
    for (final criterion in criteria) {
      buffer.writeln('- $criterion');
    }
    buffer.writeln('Prior blocking gaps:');
    for (final gap in gaps) {
      buffer.writeln(
        '- [${gap.id}] ${gap.kind} at ${gap.location}: ${gap.detail}',
      );
    }
    buffer
      ..writeln()
      ..writeln('Anti-ratchet constraints:')
      ..writeln('- Do not change the objective or acceptance criteria.')
      ..writeln(
        '- Repair only the prior blocking gaps and preserve accepted scope.',
      )
      ..writeln(
        '- Re-run the declared verification and capture fresh implementation evidence.',
      )
      ..writeln(
        '- A new objection may block only for a concrete defect or unmet gating criterion.',
      )
      ..write(
        '- Style, robustness, and test-construction preferences are non-blocking.',
      );
    return buffer.toString();
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _normalizeContractText(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  String _gapDisplayFingerprint(Ll37ObjectiveContinuationGap gap) => jsonEncode(
    {'kind': gap.kind, 'location': gap.location, 'detail': gap.detail},
  );

  Ll37ObjectiveContinuationGap _preferredGapDisplay(
    Ll37ObjectiveContinuationGap left,
    Ll37ObjectiveContinuationGap right,
  ) =>
      _gapDisplayFingerprint(left).compareTo(_gapDisplayFingerprint(right)) <= 0
      ? left
      : right;
}

class _Ll37ObjectiveContract {
  const _Ll37ObjectiveContract({
    required this.objective,
    required this.criteria,
  });

  final String objective;
  final List<String> criteria;
}
