import 'dart:async';
import 'dart:convert';
import 'dart:io';

part 'll37_verifier_fidelity_evidence.dart';
part 'll37_verifier_fidelity_json.dart';
part 'll37_verifier_fidelity_report.dart';
part 'll37_verifier_fidelity_transport.dart';

const _caseSchemaName = 'caverno_ll37_verifier_fidelity_case';
const _legacyCaseSchemaVersion = 1;
const _caseSchemaVersion = 2;
const _manifestSchemaName = 'caverno_personal_eval_case_manifest';
const _reportSchemaName = 'caverno_ll37_verifier_fidelity_report';
const _reportSchemaVersion = 3;

typedef Ll37VerifierCompletion =
    Future<String> Function(Ll37VerifierPrompt prompt);

Future<void> main(List<String> args) async {
  try {
    final options = Ll37VerifierFidelityProbeOptions.parse(args);
    if (options.showHelp) {
      stdout.writeln(Ll37VerifierFidelityProbeOptions.usage);
      return;
    }
    final report = await runLl37VerifierFidelityProbe(options: options);
    await _writeOutput(options.outJsonPath, _encodeJson(report.toJson()));
    await _writeOutput(options.outMarkdownPath, report.toMarkdown());
    stdout.write(report.toMarkdown());
    if (!report.isGo) {
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) stderr.writeln(error.path);
    exitCode = 66;
  }
}

Future<Ll37VerifierFidelityReport> runLl37VerifierFidelityProbe({
  required Ll37VerifierFidelityProbeOptions options,
  Ll37VerifierCompletion? complete,
  DateTime? generatedAt,
}) async {
  final cases = <Ll37VerifierFidelityCase>[];
  for (final path in options.casePaths) {
    cases.add(await Ll37VerifierFidelityCase.load(File(path)));
  }
  validateLl37VerifierFidelityPairs(cases);

  final completion = complete ?? _completionForOptions(options, cases);
  final results = <Ll37VerifierCaseResult>[];
  for (final evalCase in cases) {
    final prompt = Ll37VerifierPrompt.fromCase(evalCase);
    try {
      final rawResponse = await completion(prompt);
      results.add(
        Ll37VerifierCaseResult.fromResponse(
          evalCase: evalCase,
          rawResponse: rawResponse,
        ),
      );
    } catch (error) {
      results.add(
        Ll37VerifierCaseResult.invalid(
          evalCase: evalCase,
          error: error.toString(),
        ),
      );
    }
  }

  return Ll37VerifierFidelityReport.build(
    generatedAt: generatedAt ?? DateTime.now().toUtc(),
    mode: options.fixtureResponse ? 'fixture_response' : 'live_llm',
    model: options.effectiveModel,
    baseUrl: options.effectiveBaseUrl,
    results: results,
  );
}

void validateLl37VerifierFidelityPairs(List<Ll37VerifierFidelityCase> cases) {
  if (cases.isEmpty) {
    throw const FormatException('At least one LL37 evidence case is required.');
  }
  final seenCaseIds = <String>{};
  final pairs = <String, List<Ll37VerifierFidelityCase>>{};
  for (final evalCase in cases) {
    if (!seenCaseIds.add(evalCase.caseId)) {
      throw FormatException('Duplicate LL37 case id: ${evalCase.caseId}');
    }
    pairs.putIfAbsent(evalCase.pairId, () => []).add(evalCase);
  }
  for (final entry in pairs.entries) {
    final verdicts = entry.value.map((item) => item.expectedVerdict).toSet();
    if (entry.value.length != 2 ||
        !verdicts.contains(Ll37ExpectedVerdict.notRefuted) ||
        !verdicts.contains(Ll37ExpectedVerdict.refuted)) {
      throw FormatException(
        'LL37 pair ${entry.key} must contain exactly one correct '
        'and one known-broken case.',
      );
    }
    final first = entry.value.first;
    if (entry.value.any((item) => item.sourceSurface != first.sourceSurface)) {
      throw FormatException(
        'LL37 pair ${entry.key} must use one source surface.',
      );
    }
    if (entry.value.any(
      (item) =>
          item.mechanicalVerificationPassed !=
          first.mechanicalVerificationPassed,
    )) {
      throw FormatException(
        'LL37 pair ${entry.key} must share one mechanical verification '
        'status.',
      );
    }
    if (entry.value.any(
      (item) =>
          _ll37ObjectiveFingerprint(item) != _ll37ObjectiveFingerprint(first),
    )) {
      throw FormatException(
        'LL37 pair ${entry.key} must share one objective and acceptance '
        'contract.',
      );
    }
  }
}

String _ll37ObjectiveFingerprint(Ll37VerifierFidelityCase evalCase) {
  final criteria =
      evalCase.acceptanceCriteria
          .map(_normalizeLl37EvidenceText)
          .toList(growable: false)
        ..sort();
  return jsonEncode({
    'objective': _normalizeLl37EvidenceText(evalCase.objective),
    'acceptanceCriteria': criteria,
  });
}

String _normalizeLl37EvidenceText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

Ll37VerifierCompletion _completionForOptions(
  Ll37VerifierFidelityProbeOptions options,
  List<Ll37VerifierFidelityCase> cases,
) {
  if (options.fixtureResponse) {
    final expectedByCaseId = {
      for (final evalCase in cases)
        evalCase.caseId: evalCase.expectedVerdict.jsonValue,
    };
    return (prompt) async => jsonEncode({
      'verdict': expectedByCaseId[prompt.caseId],
      'confidence': 1.0,
      'findings': <Map<String, String>>[],
    });
  }
  options.validateLiveEnvironment();
  final client = OpenAiCompatibleLl37VerifierClient(
    baseUrl: options.effectiveBaseUrl,
    apiKey: options.effectiveApiKey,
    model: options.effectiveModel,
    timeout: Duration(seconds: options.timeoutSeconds),
  );
  return client.complete;
}

Future<void> _writeOutput(String? path, String contents) async {
  if (path == null) return;
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(contents.endsWith('\n') ? contents : '$contents\n');
}

String _encodeJson(Map<String, dynamic> json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';
