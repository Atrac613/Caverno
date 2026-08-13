import 'dart:convert';

enum Ll37ObjectiveSourceSurface { routine, retryUntilGreen, worktreeAgent }

enum Ll37ObjectiveVerdict { notRefuted, refuted, unverifiable }

enum Ll37ObjectiveBlocking { none, contradiction, unverifiable }

enum Ll37ObjectivePanelStatus { evaluated, skipped, cancelled }

class Ll37ObjectiveChangedFile {
  const Ll37ObjectiveChangedFile({required this.path, required this.content});

  final String path;
  final String content;

  Map<String, dynamic> toJson() => {'path': path, 'content': content};
}

class Ll37ObjectiveCandidate {
  const Ll37ObjectiveCandidate({
    required this.id,
    required this.sourceSurface,
    required this.attended,
    required this.ll34OutcomeSettled,
    required this.objective,
    required this.acceptanceCriteria,
    this.plan = '',
    this.changedFiles = const [],
    this.implementationEvidence = const [],
  });

  final String id;
  final Ll37ObjectiveSourceSurface sourceSurface;
  final bool attended;
  final bool ll34OutcomeSettled;
  final String objective;
  final List<String> acceptanceCriteria;
  final String plan;
  final List<Ll37ObjectiveChangedFile> changedFiles;
  final List<String> implementationEvidence;
}

class Ll37ObjectiveFinding {
  const Ll37ObjectiveFinding({
    required this.kind,
    required this.location,
    required this.detail,
  });

  final String kind;
  final String location;
  final String detail;
}

class Ll37ObjectivePanelVerdict {
  const Ll37ObjectivePanelVerdict({
    required this.verdict,
    required this.confidence,
    required this.blocking,
    required this.findings,
    this.error,
  });

  factory Ll37ObjectivePanelVerdict.unverifiable(String error) {
    return Ll37ObjectivePanelVerdict(
      verdict: Ll37ObjectiveVerdict.unverifiable,
      confidence: 0,
      blocking: Ll37ObjectiveBlocking.unverifiable,
      findings: const [],
      error: error,
    );
  }

  final Ll37ObjectiveVerdict verdict;
  final double confidence;
  final Ll37ObjectiveBlocking blocking;
  final List<Ll37ObjectiveFinding> findings;
  final String? error;
}

class Ll37ObjectivePanelReport {
  const Ll37ObjectivePanelReport({
    required this.status,
    required this.candidateId,
    required this.requestCount,
    required this.estimatedInputTokens,
    required this.estimatedOutputTokens,
    this.verdict,
    this.detail,
  });

  final Ll37ObjectivePanelStatus status;
  final String candidateId;
  final int requestCount;
  final int estimatedInputTokens;
  final int estimatedOutputTokens;
  final Ll37ObjectivePanelVerdict? verdict;
  final String? detail;

  int get estimatedTotalTokens => estimatedInputTokens + estimatedOutputTokens;
}

typedef Ll37ObjectiveVerifierCompletion =
    Future<String> Function(String prompt, int maxOutputTokens);

/// Signals that a route became ineligible before any verifier request began.
class Ll37ObjectiveVerifierPreconditionException implements Exception {
  const Ll37ObjectiveVerifierPreconditionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Ll37ObjectiveVerificationPanel {
  const Ll37ObjectiveVerificationPanel({
    required Ll37ObjectiveVerifierCompletion complete,
    this.maxPromptCharacters = 24000,
    this.maxOutputTokens = 768,
  }) : assert(maxPromptCharacters > 0),
       assert(maxOutputTokens > 0),
       _complete = complete;

  final Ll37ObjectiveVerifierCompletion _complete;
  final int maxPromptCharacters;
  final int maxOutputTokens;

  Future<Ll37ObjectivePanelReport> evaluate({
    required Ll37ObjectiveCandidate candidate,
    required bool Function() isCancelled,
  }) async {
    if (candidate.attended) {
      return _skipped(candidate, 'attended candidates are excluded');
    }
    if (candidate.ll34OutcomeSettled) {
      return _skipped(candidate, 'LL34 already settled the outcome');
    }
    if (candidate.objective.trim().isEmpty ||
        candidate.acceptanceCriteria.isEmpty ||
        candidate.acceptanceCriteria.any((item) => item.trim().isEmpty)) {
      return _skipped(candidate, 'objective evidence is incomplete');
    }
    if (isCancelled()) {
      return _cancelled(candidate, 'idle gate closed before verification');
    }

    final prompt = _buildPrompt(candidate);
    final inputTokens = _estimateTokens(prompt);
    if (prompt.length > maxPromptCharacters) {
      return Ll37ObjectivePanelReport(
        status: Ll37ObjectivePanelStatus.skipped,
        candidateId: candidate.id,
        requestCount: 0,
        estimatedInputTokens: inputTokens,
        estimatedOutputTokens: 0,
        detail: 'objective evidence exceeds the prompt-size limit',
      );
    }

    String rawResponse;
    try {
      rawResponse = await _complete(prompt, maxOutputTokens);
    } on Ll37ObjectiveVerifierPreconditionException catch (error) {
      return Ll37ObjectivePanelReport(
        status: Ll37ObjectivePanelStatus.skipped,
        candidateId: candidate.id,
        requestCount: 0,
        estimatedInputTokens: inputTokens,
        estimatedOutputTokens: 0,
        detail: error.message,
      );
    } catch (error) {
      return Ll37ObjectivePanelReport(
        status: Ll37ObjectivePanelStatus.evaluated,
        candidateId: candidate.id,
        requestCount: 1,
        estimatedInputTokens: inputTokens,
        estimatedOutputTokens: 0,
        verdict: Ll37ObjectivePanelVerdict.unverifiable(error.toString()),
        detail: 'verifier request failed',
      );
    }
    if (isCancelled()) {
      return Ll37ObjectivePanelReport(
        status: Ll37ObjectivePanelStatus.cancelled,
        candidateId: candidate.id,
        requestCount: 1,
        estimatedInputTokens: inputTokens,
        estimatedOutputTokens: _estimateTokens(rawResponse),
        detail: 'idle gate closed during verification',
      );
    }

    final verdict = _parseVerdict(rawResponse);
    return Ll37ObjectivePanelReport(
      status: Ll37ObjectivePanelStatus.evaluated,
      candidateId: candidate.id,
      requestCount: 1,
      estimatedInputTokens: inputTokens,
      estimatedOutputTokens: _estimateTokens(rawResponse),
      verdict: verdict,
      detail: verdict.error == null
          ? 'objective verification completed'
          : 'verifier output was invalid',
    );
  }

  Ll37ObjectivePanelReport _skipped(
    Ll37ObjectiveCandidate candidate,
    String detail,
  ) {
    return Ll37ObjectivePanelReport(
      status: Ll37ObjectivePanelStatus.skipped,
      candidateId: candidate.id,
      requestCount: 0,
      estimatedInputTokens: 0,
      estimatedOutputTokens: 0,
      detail: detail,
    );
  }

  Ll37ObjectivePanelReport _cancelled(
    Ll37ObjectiveCandidate candidate,
    String detail,
  ) {
    return Ll37ObjectivePanelReport(
      status: Ll37ObjectivePanelStatus.cancelled,
      candidateId: candidate.id,
      requestCount: 0,
      estimatedInputTokens: 0,
      estimatedOutputTokens: 0,
      detail: detail,
    );
  }

  String _buildPrompt(Ll37ObjectiveCandidate candidate) {
    final evidence = {
      'candidateId': candidate.id,
      'sourceSurface': candidate.sourceSurface.name,
      'objective': candidate.objective,
      'acceptanceCriteria': candidate.acceptanceCriteria,
      'plan': candidate.plan,
      'changedFiles': candidate.changedFiles
          .map((file) => file.toJson())
          .toList(growable: false),
      'implementationEvidence': candidate.implementationEvidence,
    };
    return '''
Audit whether this unattended implementation satisfies its declared objective.
Do not call tools, propose edits, or infer missing evidence. Refute only for a
concrete cited defect or unmet acceptance criterion. Return JSON only:
{"verdict":"not_refuted|refuted|unverifiable","confidence":0.0,"blocking":"none|contradiction|unverifiable","findings":[{"kind":"...","location":"...","detail":"..."}]}

Evidence:
${jsonEncode(evidence)}
'''
        .trim();
  }

  Ll37ObjectivePanelVerdict _parseVerdict(String rawResponse) {
    try {
      final decoded = jsonDecode(rawResponse);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('verifier response must be a JSON object');
      }
      final verdict = switch (decoded['verdict']) {
        'not_refuted' => Ll37ObjectiveVerdict.notRefuted,
        'refuted' => Ll37ObjectiveVerdict.refuted,
        'unverifiable' => Ll37ObjectiveVerdict.unverifiable,
        _ => throw const FormatException('unknown verifier verdict'),
      };
      final blocking = switch (decoded['blocking']) {
        'none' => Ll37ObjectiveBlocking.none,
        'contradiction' => Ll37ObjectiveBlocking.contradiction,
        'unverifiable' => Ll37ObjectiveBlocking.unverifiable,
        _ => throw const FormatException('unknown blocking classification'),
      };
      final confidenceValue = decoded['confidence'];
      if (confidenceValue is! num ||
          confidenceValue < 0 ||
          confidenceValue > 1) {
        throw const FormatException('confidence must be between zero and one');
      }
      final rawFindings = decoded['findings'];
      if (rawFindings is! List) {
        throw const FormatException('findings must be a list');
      }
      final findings = rawFindings
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('finding must be an object');
            }
            return Ll37ObjectiveFinding(
              kind: _requiredResponseString(item, 'kind'),
              location: _requiredResponseString(item, 'location'),
              detail: _requiredResponseString(item, 'detail'),
            );
          })
          .toList(growable: false);
      if (verdict == Ll37ObjectiveVerdict.refuted && findings.isEmpty) {
        throw const FormatException('a refutation requires a concrete finding');
      }
      if (verdict == Ll37ObjectiveVerdict.notRefuted &&
          blocking != Ll37ObjectiveBlocking.none) {
        throw const FormatException('not-refuted output cannot be blocking');
      }
      if (verdict == Ll37ObjectiveVerdict.unverifiable &&
          blocking != Ll37ObjectiveBlocking.unverifiable) {
        throw const FormatException(
          'unverifiable output requires unverifiable blocking',
        );
      }
      if (verdict == Ll37ObjectiveVerdict.refuted &&
          blocking != Ll37ObjectiveBlocking.contradiction) {
        throw const FormatException(
          'refuted output requires contradiction blocking',
        );
      }
      return Ll37ObjectivePanelVerdict(
        verdict: verdict,
        confidence: confidenceValue.toDouble(),
        blocking: blocking,
        findings: findings,
      );
    } catch (error) {
      return Ll37ObjectivePanelVerdict.unverifiable(error.toString());
    }
  }
}

String _requiredResponseString(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return result.trim();
}

int _estimateTokens(String value) => (value.length + 3) ~/ 4;
