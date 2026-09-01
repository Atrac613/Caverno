import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const rag3SupportFilterLatencyDecisionSchema =
    'caverno_rag3_support_filter_latency_decision';
const rag3SupportFilterLatencyDecisionContract =
    'rag3-support-filter-latency-decision-v1';
const rag3SupportFilterMaximumAddedP95LatencyMs = 1200;
const rag3SupportFilterExpectedInstrumentContract =
    'rag3-batched-support-filter-v2';
const rag3SupportFilterExpectedFixtureId = 'rag2-compositional-holdout-v1';
const rag3SupportFilterExpectedRequestCount = 20;

Future<void> main(List<String> args) async {
  final options = Rag3SupportFilterLatencyDecisionOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag3_support_filter_latency_decision.dart '
      '--report PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag3SupportFilterLatencyDecision(options);
    stdout.write(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG3 support-filter latency decision failed: $error');
    exitCode = 65;
  }
}

Future<Rag3SupportFilterLatencyDecisionReport>
runRag3SupportFilterLatencyDecision(
  Rag3SupportFilterLatencyDecisionOptions options,
) async {
  final output = Directory(options.outDir);
  if (output.existsSync() && output.listSync().isNotEmpty) {
    throw StateError(
      'RAG3 support-filter latency output already exists; refusing rerun.',
    );
  }
  final reportFile = File(options.reportPath);
  final bytes = await reportFile.readAsBytes();
  final decoded = (jsonDecode(utf8.decode(bytes)) as Map)
      .cast<String, Object?>();
  final evidence = Rag3SupportFilterLatencyEvidence.parse(decoded);
  final report = Rag3SupportFilterLatencyDecisionReport(
    sourceReportSha256: sha256.convert(bytes).toString(),
    evidence: evidence,
  );
  await output.create(recursive: true);
  await File(
    '${output.path}/rag3_support_filter_latency_decision.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${output.path}/rag3_support_filter_latency_decision.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

final class Rag3SupportFilterLatencyDecisionOptions {
  const Rag3SupportFilterLatencyDecisionOptions({
    required this.reportPath,
    required this.outDir,
  });

  final String reportPath;
  final String outDir;

  static Rag3SupportFilterLatencyDecisionOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length || !args[index].startsWith('--')) {
        return null;
      }
      if (values.containsKey(args[index])) return null;
      values[args[index]] = args[index + 1];
    }
    const required = {'--report', '--out-dir'};
    if (values.keys.toSet().length != required.length ||
        !values.keys.toSet().containsAll(required) ||
        values.values.any((item) => item.trim().isEmpty)) {
      return null;
    }
    return Rag3SupportFilterLatencyDecisionOptions(
      reportPath: values['--report']!,
      outDir: values['--out-dir']!,
    );
  }
}

final class Rag3SupportFilterLatencyEvidence {
  const Rag3SupportFilterLatencyEvidence({
    required this.buildCommit,
    required this.fixtureId,
    required this.requestedModelId,
    required this.responseModelId,
    required this.requestCount,
    required this.truePositive,
    required this.trueNegative,
    required this.falsePositive,
    required this.falseNegative,
    required this.unavailableCount,
    required this.invalidCount,
    required this.p50LatencyMs,
    required this.p95LatencyMs,
  });

  factory Rag3SupportFilterLatencyEvidence.parse(Map<String, Object?> json) {
    final responseModelIds = _stringList(json, 'responseModelIds');
    final classifier = _map(json, 'classifier');
    final metrics = _map(classifier, 'metrics');
    if (_string(json, 'schemaName') !=
            'caverno_rag3_batched_support_filter_instrument' ||
        _integer(json, 'schemaVersion') != 1 ||
        _string(json, 'contract') !=
            rag3SupportFilterExpectedInstrumentContract ||
        _boolean(json, 'buildDirty') ||
        _string(json, 'sourceFixtureId') !=
            rag3SupportFilterExpectedFixtureId ||
        _integer(json, 'requestCount') !=
            rag3SupportFilterExpectedRequestCount ||
        _boolean(json, 'queryOrEvidencePersisted') ||
        json['classifierFailureReason'] != null ||
        responseModelIds.length != 1 ||
        responseModelIds.single != _string(json, 'requestedModelId') ||
        _string(json, 'productionDecision') != 'no_go' ||
        _string(json, 'promotionDecision') != 'not_run' ||
        _string(classifier, 'schemaName') !=
            'caverno_rag3_batched_support_filter_report' ||
        _string(classifier, 'contract') !=
            rag3SupportFilterExpectedInstrumentContract ||
        _string(classifier, 'fixtureId') !=
            rag3SupportFilterExpectedFixtureId ||
        _string(classifier, 'instrumentDecision') != 'go' ||
        _string(classifier, 'latencyDecision') != 'measurement_only' ||
        _string(classifier, 'activationDecision') !=
            'blocked_pending_latency_contract') {
      throw const FormatException(
        'RAG3 support-filter latency evidence violates the frozen identity.',
      );
    }
    final evidence = Rag3SupportFilterLatencyEvidence(
      buildCommit: _string(json, 'buildCommit'),
      fixtureId: _string(json, 'sourceFixtureId'),
      requestedModelId: _string(json, 'requestedModelId'),
      responseModelId: responseModelIds.single,
      requestCount: _integer(json, 'requestCount'),
      truePositive: _integer(metrics, 'truePositive'),
      trueNegative: _integer(metrics, 'trueNegative'),
      falsePositive: _integer(metrics, 'falsePositive'),
      falseNegative: _integer(metrics, 'falseNegative'),
      unavailableCount: _integer(classifier, 'unavailableCount'),
      invalidCount: _integer(classifier, 'invalidCount'),
      p50LatencyMs: _integer(classifier, 'p50LatencyMs'),
      p95LatencyMs: _integer(classifier, 'p95LatencyMs'),
    );
    if (evidence.buildCommit.trim().isEmpty ||
        evidence.truePositive <= 0 ||
        evidence.trueNegative <= 0 ||
        evidence.falsePositive < 0 ||
        evidence.falseNegative < 0 ||
        evidence.unavailableCount < 0 ||
        evidence.invalidCount < 0 ||
        evidence.p50LatencyMs <= 0 ||
        evidence.p95LatencyMs < evidence.p50LatencyMs ||
        evidence.truePositive +
                evidence.trueNegative +
                evidence.falsePositive +
                evidence.falseNegative !=
            100 ||
        !evidence.qualityPassed) {
      throw const FormatException(
        'RAG3 support-filter latency evidence contains invalid measurements.',
      );
    }
    return evidence;
  }

  final String buildCommit;
  final String fixtureId;
  final String requestedModelId;
  final String responseModelId;
  final int requestCount;
  final int truePositive;
  final int trueNegative;
  final int falsePositive;
  final int falseNegative;
  final int unavailableCount;
  final int invalidCount;
  final int p50LatencyMs;
  final int p95LatencyMs;

  bool get qualityPassed =>
      falsePositive == 0 &&
      falseNegative == 0 &&
      unavailableCount == 0 &&
      invalidCount == 0;

  Map<String, Object?> toJson() => {
    'buildCommit': buildCommit,
    'fixtureId': fixtureId,
    'requestedModelId': requestedModelId,
    'responseModelId': responseModelId,
    'requestCount': requestCount,
    'truePositive': truePositive,
    'trueNegative': trueNegative,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'unavailableCount': unavailableCount,
    'invalidCount': invalidCount,
    'p50LatencyMs': p50LatencyMs,
    'p95LatencyMs': p95LatencyMs,
  };
}

final class Rag3SupportFilterLatencyDecisionReport {
  const Rag3SupportFilterLatencyDecisionReport({
    required this.sourceReportSha256,
    required this.evidence,
  });

  final String sourceReportSha256;
  final Rag3SupportFilterLatencyEvidence evidence;

  bool get inlineEligible =>
      evidence.qualityPassed &&
      evidence.p95LatencyMs <= rag3SupportFilterMaximumAddedP95LatencyMs;
  bool get shadowEligible => evidence.qualityPassed;
  double get p95BudgetMultiple =>
      evidence.p95LatencyMs / rag3SupportFilterMaximumAddedP95LatencyMs;

  Map<String, Object?> toJson() => {
    'schemaName': rag3SupportFilterLatencyDecisionSchema,
    'schemaVersion': 1,
    'contract': rag3SupportFilterLatencyDecisionContract,
    'sourceReportSha256': sourceReportSha256,
    'maximumAddedP95LatencyMs': rag3SupportFilterMaximumAddedP95LatencyMs,
    'p95BudgetMultiple': p95BudgetMultiple,
    'qualityDecision': evidence.qualityPassed ? 'go' : 'no_go',
    'inlineDecision': inlineEligible ? 'go' : 'no_go',
    'shadowDecision': shadowEligible ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'promotionDecision': 'not_run',
    'evidence': evidence.toJson(),
  };

  String toMarkdown() =>
      '# RAG3 Support-Filter Latency Decision\n\n'
      '- Model: `${evidence.requestedModelId}`\n'
      '- p50 batch latency: `${evidence.p50LatencyMs} ms`\n'
      '- p95 batch latency: `${evidence.p95LatencyMs} ms`\n'
      '- Maximum added p95 latency: '
      '`$rag3SupportFilterMaximumAddedP95LatencyMs ms`\n'
      '- p95 budget multiple: `${p95BudgetMultiple.toStringAsFixed(2)}x`\n'
      '- Quality decision: `${evidence.qualityPassed ? 'go' : 'no_go'}`\n'
      '- Inline decision: `${inlineEligible ? 'go' : 'no_go'}`\n'
      '- Shadow decision: `${shadowEligible ? 'go' : 'no_go'}`\n'
      '- Production decision: `no_go`\n'
      '- Promotion decision: `not_run`\n';
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be a JSON object.');
  return value.cast<String, Object?>();
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

bool _boolean(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must be a string array.');
  }
  return value.cast<String>();
}
