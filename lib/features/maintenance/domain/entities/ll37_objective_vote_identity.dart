import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable identity for one bounded LL37 verifier slot.
class Ll37ObjectiveVoteIdentity {
  const Ll37ObjectiveVoteIdentity._();

  static const schemaVersion = 1;
  static const maxVotesPerCandidate = 3;

  static String build({
    required String candidateId,
    required String verifierProfileKey,
    required String fidelityReportSha256,
    required int voteIndex,
  }) {
    final normalizedCandidateId = _required(candidateId, 'candidateId');
    final normalizedProfileKey = _required(
      verifierProfileKey,
      'verifierProfileKey',
    );
    final normalizedReportSha = _required(
      fidelityReportSha256,
      'fidelityReportSha256',
    ).toLowerCase();
    if (voteIndex < 1 || voteIndex > maxVotesPerCandidate) {
      throw RangeError.range(voteIndex, 1, maxVotesPerCandidate, 'voteIndex');
    }
    final canonical = jsonEncode({
      'schemaVersion': schemaVersion,
      'candidateId': normalizedCandidateId,
      'verifierProfileKey': normalizedProfileKey,
      'fidelityReportSha256': normalizedReportSha,
      'voteIndex': voteIndex,
    });
    return 'll37-v$schemaVersion-${sha256.convert(utf8.encode(canonical))}';
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw FormatException('$field must be a non-empty string');
    }
    return normalized;
  }
}
