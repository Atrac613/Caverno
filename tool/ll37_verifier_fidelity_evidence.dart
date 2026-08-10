part of 'll37_verifier_fidelity_probe.dart';

enum Ll37SourceSurface {
  routine('routine'),
  retryUntilGreen('retry_until_green'),
  worktreeAgent('worktree_agent'),
  synthetic('synthetic');

  const Ll37SourceSurface(this.jsonValue);

  final String jsonValue;

  bool get isEligible => this != Ll37SourceSurface.synthetic;

  static Ll37SourceSurface parse(String value, String path) {
    return values.firstWhere(
      (item) => item.jsonValue == value,
      orElse: () => throw FormatException(
        'Unsupported LL37 source surface `$value` in $path.',
      ),
    );
  }
}

enum Ll37ExpectedVerdict {
  refuted('refuted'),
  notRefuted('not_refuted');

  const Ll37ExpectedVerdict(this.jsonValue);

  final String jsonValue;

  static Ll37ExpectedVerdict parse(String value, String path) {
    return values.firstWhere(
      (item) => item.jsonValue == value,
      orElse: () => throw FormatException(
        'Unsupported LL37 expected verdict `$value` in $path.',
      ),
    );
  }
}

enum Ll37VerifierVerdict {
  refuted('refuted'),
  notRefuted('not_refuted'),
  unverifiable('unverifiable');

  const Ll37VerifierVerdict(this.jsonValue);

  final String jsonValue;

  static Ll37VerifierVerdict? tryParse(String value) {
    for (final item in values) {
      if (item.jsonValue == value) return item;
    }
    return null;
  }
}

final class Ll37VerifierFidelityCase {
  const Ll37VerifierFidelityCase({
    required this.caseId,
    required this.pairId,
    required this.title,
    required this.sourceSurface,
    required this.expectedVerdict,
    required this.objective,
    required this.acceptanceCriteria,
    required this.changedFiles,
    required this.verificationEvidence,
    required this.casePath,
    required this.personalEvalManifestPath,
  });

  final String caseId;
  final String pairId;
  final String title;
  final Ll37SourceSurface sourceSurface;
  final Ll37ExpectedVerdict expectedVerdict;
  final String objective;
  final List<String> acceptanceCriteria;
  final List<Map<String, dynamic>> changedFiles;
  final List<Map<String, dynamic>> verificationEvidence;
  final String casePath;
  final String personalEvalManifestPath;

  static Future<Ll37VerifierFidelityCase> load(File caseFile) async {
    if (!caseFile.existsSync()) {
      throw FileSystemException('LL37 evidence case not found.', caseFile.path);
    }
    final json = _decodeObject(await caseFile.readAsString(), caseFile.path);
    if (_string(json['schemaName']) != _caseSchemaName ||
        _integer(json['schemaVersion']) != _caseSchemaVersion) {
      throw FormatException(
        'Invalid LL37 evidence schema in ${caseFile.path}.',
      );
    }
    final caseId = _requiredString(json, 'caseId', caseFile.path);
    final manifestRef = _requiredString(
      json,
      'personalEvalManifestPath',
      caseFile.path,
    );
    final manifestFile = _resolveRelativeFile(caseFile, manifestRef);
    final manifest = await _loadPersonalEvalManifest(
      manifestFile,
      expectedCaseId: caseId,
    );
    final expectedVerdict = Ll37ExpectedVerdict.parse(
      _requiredString(json, 'expectedVerdict', caseFile.path),
      caseFile.path,
    );

    final criteria = _stringList(json['acceptanceCriteria']);
    if (criteria.isEmpty) {
      throw FormatException(
        'LL37 case $caseId must include acceptance criteria.',
      );
    }
    final changedFiles = _objectList(json['changedFiles']);
    if (changedFiles.isEmpty &&
        expectedVerdict == Ll37ExpectedVerdict.notRefuted) {
      throw FormatException(
        'Correct LL37 case $caseId must include changed files.',
      );
    }
    final verificationEvidence = _objectList(json['verificationEvidence']);
    if (verificationEvidence.isEmpty) {
      throw FormatException(
        'LL37 case $caseId must include verification evidence.',
      );
    }

    return Ll37VerifierFidelityCase(
      caseId: caseId,
      pairId: _requiredString(json, 'pairId', caseFile.path),
      title: _requiredString(json, 'title', caseFile.path),
      sourceSurface: Ll37SourceSurface.parse(
        _requiredString(json, 'sourceSurface', caseFile.path),
        caseFile.path,
      ),
      expectedVerdict: expectedVerdict,
      objective: manifest.objective,
      acceptanceCriteria: List.unmodifiable(criteria),
      changedFiles: List.unmodifiable(changedFiles),
      verificationEvidence: List.unmodifiable(verificationEvidence),
      casePath: caseFile.path,
      personalEvalManifestPath: manifestFile.path,
    );
  }
}

final class _PersonalEvalManifest {
  const _PersonalEvalManifest({required this.objective});

  final String objective;
}

Future<_PersonalEvalManifest> _loadPersonalEvalManifest(
  File file, {
  required String expectedCaseId,
}) async {
  if (!file.existsSync()) {
    throw FileSystemException('Personal eval manifest not found.', file.path);
  }
  final json = _decodeObject(await file.readAsString(), file.path);
  if (_string(json['schemaName']) != _manifestSchemaName ||
      _integer(json['schemaVersion']) != 1) {
    throw FormatException('Invalid personal eval manifest in ${file.path}.');
  }
  final caseId = _requiredString(json, 'caseId', file.path);
  if (caseId != expectedCaseId) {
    throw FormatException(
      'LL37 case $expectedCaseId does not match manifest case $caseId.',
    );
  }
  if (_string(json['readiness']) != 'ready') {
    throw FormatException('Personal eval case $caseId is not ready.');
  }
  final consent = _object(json['consent']);
  if (consent?['explicitUserConsent'] != true) {
    throw FormatException('Personal eval case $caseId lacks explicit consent.');
  }
  final task = _object(json['task']);
  final objective = _string(task?['prompt'])?.trim() ?? '';
  final verificationCommand =
      _string(task?['verificationCommand'])?.trim() ?? '';
  if (objective.isEmpty || verificationCommand.isEmpty) {
    throw FormatException(
      'Personal eval case $caseId lacks an objective or verification command.',
    );
  }
  return _PersonalEvalManifest(objective: objective);
}

final class Ll37VerifierPrompt {
  const Ll37VerifierPrompt({
    required this.caseId,
    required this.systemPrompt,
    required this.userPrompt,
  });

  final String caseId;
  final String systemPrompt;
  final String userPrompt;

  factory Ll37VerifierPrompt.fromCase(Ll37VerifierFidelityCase evalCase) {
    const systemPrompt =
        'You are an objective verifier for unattended coding work. Audit the '
        'provided implementation evidence against the objective and every '
        'acceptance criterion. Refute only for a concrete cited defect or '
        'unmet criterion, never for style, robustness preferences, or missing '
        'tests that are not required. Use unverifiable when the supplied '
        'evidence cannot decide. Return one JSON object only with verdict '
        '(refuted, not_refuted, or unverifiable), confidence from 0 to 1, and '
        'findings as objects with kind, location, and detail.';
    return Ll37VerifierPrompt(
      caseId: evalCase.caseId,
      systemPrompt: systemPrompt,
      userPrompt: const JsonEncoder.withIndent('  ').convert({
        'objective': evalCase.objective,
        'acceptanceCriteria': evalCase.acceptanceCriteria,
        'changedFiles': evalCase.changedFiles,
        'verificationEvidence': evalCase.verificationEvidence,
      }),
    );
  }
}

final class Ll37VerifierFinding {
  const Ll37VerifierFinding({
    required this.kind,
    required this.location,
    required this.detail,
  });

  final String kind;
  final String location;
  final String detail;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'location': location,
    'detail': detail,
  };
}

final class Ll37VerifierCaseResult {
  const Ll37VerifierCaseResult({
    required this.evalCase,
    required this.rawResponse,
    required this.verdict,
    required this.confidence,
    required this.findings,
    this.error,
  });

  factory Ll37VerifierCaseResult.invalid({
    required Ll37VerifierFidelityCase evalCase,
    required String error,
    String rawResponse = '',
  }) {
    return Ll37VerifierCaseResult(
      evalCase: evalCase,
      rawResponse: rawResponse,
      verdict: null,
      confidence: null,
      findings: const [],
      error: error,
    );
  }

  factory Ll37VerifierCaseResult.fromResponse({
    required Ll37VerifierFidelityCase evalCase,
    required String rawResponse,
  }) {
    try {
      final json = _decodeResponseObject(rawResponse);
      final verdict = Ll37VerifierVerdict.tryParse(
        _string(json['verdict']) ?? '',
      );
      final confidence = json['confidence'];
      if (verdict == null || confidence is! num) {
        throw const FormatException(
          'Verifier response lacks a supported verdict or confidence.',
        );
      }
      final normalizedConfidence = confidence.toDouble();
      if (normalizedConfidence < 0 || normalizedConfidence > 1) {
        throw const FormatException(
          'Verifier confidence must be between 0 and 1.',
        );
      }
      final findings = <Ll37VerifierFinding>[];
      for (final rawFinding in _objectList(json['findings'])) {
        findings.add(
          Ll37VerifierFinding(
            kind: _requiredString(rawFinding, 'kind', 'verifier response'),
            location: _requiredString(
              rawFinding,
              'location',
              'verifier response',
            ),
            detail: _requiredString(rawFinding, 'detail', 'verifier response'),
          ),
        );
      }
      return Ll37VerifierCaseResult(
        evalCase: evalCase,
        rawResponse: rawResponse,
        verdict: verdict,
        confidence: normalizedConfidence,
        findings: List.unmodifiable(findings),
      );
    } on FormatException catch (error) {
      return Ll37VerifierCaseResult.invalid(
        evalCase: evalCase,
        rawResponse: rawResponse,
        error: error.message,
      );
    }
  }

  final Ll37VerifierFidelityCase evalCase;
  final String rawResponse;
  final Ll37VerifierVerdict? verdict;
  final double? confidence;
  final List<Ll37VerifierFinding> findings;
  final String? error;

  bool get isValid => verdict != null && error == null;

  bool get matchesExpected {
    return switch ((evalCase.expectedVerdict, verdict)) {
      (Ll37ExpectedVerdict.refuted, Ll37VerifierVerdict.refuted) => true,
      (Ll37ExpectedVerdict.notRefuted, Ll37VerifierVerdict.notRefuted) => true,
      _ => false,
    };
  }

  Map<String, dynamic> toJson() => {
    'caseId': evalCase.caseId,
    'pairId': evalCase.pairId,
    'title': evalCase.title,
    'sourceSurface': evalCase.sourceSurface.jsonValue,
    'eligible': evalCase.sourceSurface.isEligible,
    'expectedVerdict': evalCase.expectedVerdict.jsonValue,
    if (verdict != null) 'verdict': verdict!.jsonValue,
    if (confidence != null) 'confidence': confidence,
    'matchesExpected': matchesExpected,
    'findings': findings.map((item) => item.toJson()).toList(growable: false),
    if (error != null) 'error': error,
    'casePath': evalCase.casePath,
    'personalEvalManifestPath': evalCase.personalEvalManifestPath,
  };
}
