import 'll37_objective_vote_identity.dart';

class Ll37ObjectiveVerdictFindingRecord {
  const Ll37ObjectiveVerdictFindingRecord({
    required this.kind,
    required this.location,
    required this.detail,
  });

  final String kind;
  final String location;
  final String detail;

  factory Ll37ObjectiveVerdictFindingRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return Ll37ObjectiveVerdictFindingRecord(
      kind: _requiredString(json, 'kind'),
      location: _requiredString(json, 'location'),
      detail: _requiredString(json, 'detail'),
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'location': location,
    'detail': detail,
  };
}

/// Bounded persistent projection of one evaluated LL37 objective verdict.
class Ll37ObjectiveVerdictRecord {
  Ll37ObjectiveVerdictRecord({
    required this.voteId,
    required this.voteIndex,
    required this.candidateId,
    required this.sourceSurface,
    required this.objective,
    required List<String> acceptanceCriteria,
    required List<String> changedFilePaths,
    required List<String> implementationEvidence,
    required this.verdict,
    required this.confidence,
    required this.blocking,
    required List<Ll37ObjectiveVerdictFindingRecord> findings,
    required this.requestCount,
    required this.estimatedInputTokens,
    required this.estimatedOutputTokens,
    required this.verifierProvider,
    required this.verifierBaseUrl,
    required this.verifierModel,
    required this.verifierProfileKey,
    required this.fidelityReportSchemaVersion,
    required this.fidelityReportSha256,
    required this.recordedAt,
    this.error,
    this.detail,
  }) : acceptanceCriteria = List.unmodifiable(acceptanceCriteria),
       changedFilePaths = List.unmodifiable(changedFilePaths),
       implementationEvidence = List.unmodifiable(implementationEvidence),
       findings = List.unmodifiable(findings);

  static const schemaVersion = 2;

  final String voteId;
  final int voteIndex;
  final String candidateId;
  final String sourceSurface;
  final String objective;
  final List<String> acceptanceCriteria;
  final List<String> changedFilePaths;
  final List<String> implementationEvidence;
  final String verdict;
  final double confidence;
  final String blocking;
  final List<Ll37ObjectiveVerdictFindingRecord> findings;
  final String? error;
  final String? detail;
  final int requestCount;
  final int estimatedInputTokens;
  final int estimatedOutputTokens;
  final String verifierProvider;
  final String verifierBaseUrl;
  final String verifierModel;
  final String verifierProfileKey;
  final int fidelityReportSchemaVersion;
  final String fidelityReportSha256;
  final DateTime recordedAt;

  int get estimatedTotalTokens => estimatedInputTokens + estimatedOutputTokens;

  factory Ll37ObjectiveVerdictRecord.fromJson(Map<String, dynamic> json) {
    final storedSchemaVersion = json['schemaVersion'];
    if (storedSchemaVersion != 1 && storedSchemaVersion != schemaVersion) {
      throw const FormatException('unsupported LL37 verdict schema version');
    }
    final confidence = json['confidence'];
    if (confidence is! num || confidence < 0 || confidence > 1) {
      throw const FormatException('confidence must be between zero and one');
    }
    final recordedAt = DateTime.tryParse(_requiredString(json, 'recordedAt'));
    if (recordedAt == null) {
      throw const FormatException('recordedAt must be an ISO-8601 timestamp');
    }
    final sourceSurface = _requiredString(json, 'sourceSurface');
    if (!const {
      'routine',
      'retryUntilGreen',
      'worktreeAgent',
    }.contains(sourceSurface)) {
      throw const FormatException('unknown LL37 source surface');
    }
    final verdict = _requiredString(json, 'verdict');
    if (!const {'notRefuted', 'refuted', 'unverifiable'}.contains(verdict)) {
      throw const FormatException('unknown LL37 verdict');
    }
    final blocking = _requiredString(json, 'blocking');
    if (!const {'none', 'contradiction', 'unverifiable'}.contains(blocking)) {
      throw const FormatException('unknown LL37 blocking classification');
    }
    final rawFindings = json['findings'];
    if (rawFindings is! List) {
      throw const FormatException('findings must be a list');
    }
    final acceptanceCriteria = _requiredStringList(json, 'acceptanceCriteria');
    final changedFilePaths = _requiredStringList(json, 'changedFilePaths');
    if (acceptanceCriteria.isEmpty || changedFilePaths.isEmpty) {
      throw const FormatException(
        'acceptance criteria and changed-file paths must not be empty',
      );
    }
    final findings = rawFindings
        .map(
          (item) => Ll37ObjectiveVerdictFindingRecord.fromJson(
            _requiredMap(item, 'finding'),
          ),
        )
        .toList(growable: false);
    if (verdict == 'refuted' && findings.isEmpty) {
      throw const FormatException('a refutation requires a concrete finding');
    }
    if (verdict == 'notRefuted' && blocking != 'none') {
      throw const FormatException('not-refuted verdict cannot be blocking');
    }
    if (verdict == 'unverifiable' && blocking != 'unverifiable') {
      throw const FormatException(
        'unverifiable verdict requires unverifiable blocking',
      );
    }
    if (verdict == 'refuted' && blocking != 'contradiction') {
      throw const FormatException(
        'refuted verdict requires contradiction blocking',
      );
    }
    final candidateId = _requiredString(json, 'candidateId');
    final verifierProfileKey = _requiredString(json, 'verifierProfileKey');
    final fidelityReportSha256 = _requiredString(json, 'fidelityReportSha256');
    final voteIndex = storedSchemaVersion == 1
        ? 1
        : _requiredPositiveInt(json, 'voteIndex');
    if (voteIndex > Ll37ObjectiveVoteIdentity.maxVotesPerCandidate) {
      throw const FormatException('voteIndex exceeds the LL37 vote cap');
    }
    final expectedVoteId = Ll37ObjectiveVoteIdentity.build(
      candidateId: candidateId,
      verifierProfileKey: verifierProfileKey,
      fidelityReportSha256: fidelityReportSha256,
      voteIndex: voteIndex,
    );
    final voteId = storedSchemaVersion == 1
        ? expectedVoteId
        : _requiredString(json, 'voteId');
    if (voteId != expectedVoteId) {
      throw const FormatException('voteId does not match its immutable slot');
    }
    return Ll37ObjectiveVerdictRecord(
      voteId: voteId,
      voteIndex: voteIndex,
      candidateId: candidateId,
      sourceSurface: sourceSurface,
      objective: _requiredString(json, 'objective'),
      acceptanceCriteria: acceptanceCriteria,
      changedFilePaths: changedFilePaths,
      implementationEvidence: _requiredStringList(
        json,
        'implementationEvidence',
      ),
      verdict: verdict,
      confidence: confidence.toDouble(),
      blocking: blocking,
      findings: findings,
      error: _optionalString(json, 'error'),
      detail: _optionalString(json, 'detail'),
      requestCount: _requiredNonNegativeInt(json, 'requestCount'),
      estimatedInputTokens: _requiredNonNegativeInt(
        json,
        'estimatedInputTokens',
      ),
      estimatedOutputTokens: _requiredNonNegativeInt(
        json,
        'estimatedOutputTokens',
      ),
      verifierProvider: _requiredString(json, 'verifierProvider'),
      verifierBaseUrl: _requiredString(json, 'verifierBaseUrl'),
      verifierModel: _requiredString(json, 'verifierModel'),
      verifierProfileKey: verifierProfileKey,
      fidelityReportSchemaVersion: _requiredNonNegativeInt(
        json,
        'fidelityReportSchemaVersion',
      ),
      fidelityReportSha256: fidelityReportSha256,
      recordedAt: recordedAt.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'voteId': voteId,
    'voteIndex': voteIndex,
    'candidateId': candidateId,
    'sourceSurface': sourceSurface,
    'objective': objective,
    'acceptanceCriteria': acceptanceCriteria,
    'changedFilePaths': changedFilePaths,
    'implementationEvidence': implementationEvidence,
    'verdict': verdict,
    'confidence': confidence,
    'blocking': blocking,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    if (error != null) 'error': error,
    if (detail != null) 'detail': detail,
    'requestCount': requestCount,
    'estimatedInputTokens': estimatedInputTokens,
    'estimatedOutputTokens': estimatedOutputTokens,
    'verifierProvider': verifierProvider,
    'verifierBaseUrl': verifierBaseUrl,
    'verifierModel': verifierModel,
    'verifierProfileKey': verifierProfileKey,
    'fidelityReportSchemaVersion': fidelityReportSchemaVersion,
    'fidelityReportSha256': fidelityReportSha256,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _requiredMap(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

String _requiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$field must be a string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _requiredStringList(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! List) {
    throw FormatException('$field must be a list');
  }
  return value
      .map((item) {
        if (item is! String || item.trim().isEmpty) {
          throw FormatException('$field must contain non-empty strings');
        }
        return item.trim();
      })
      .toList(growable: false);
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! int || value < 0) {
    throw FormatException('$field must be a non-negative integer');
  }
  return value;
}

int _requiredPositiveInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! int || value < 1) {
    throw FormatException('$field must be a positive integer');
  }
  return value;
}
