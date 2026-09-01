import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_support_filter_latency_decision.dart';

void main() {
  test('rejects the measured inline latency but keeps shadow eligible', () {
    final report = _decision(p95LatencyMs: 6464);

    expect(report.evidence.qualityPassed, isTrue);
    expect(report.inlineEligible, isFalse);
    expect(report.shadowEligible, isTrue);
    expect(report.p95BudgetMultiple, closeTo(5.3867, 0.0001));
    expect(report.toJson(), containsPair('inlineDecision', 'no_go'));
    expect(report.toJson(), containsPair('shadowDecision', 'go'));
    expect(report.toJson(), containsPair('productionDecision', 'no_go'));
  });

  test('accepts the exact p95 boundary and rejects one millisecond over', () {
    expect(_decision(p95LatencyMs: 1200).inlineEligible, isTrue);
    expect(_decision(p95LatencyMs: 1201).inlineEligible, isFalse);
  });

  test('rejects evidence that contradicts the quality-Go identity', () {
    expect(
      () => Rag3SupportFilterLatencyEvidence.parse(
        _instrumentJson(falsePositive: 1),
      ),
      throwsFormatException,
    );
  });

  test('rejects dirty, content-bearing, or mismatched evidence', () {
    for (final mutate in <void Function(Map<String, Object?>)>[
      (json) => json['buildDirty'] = true,
      (json) => json['queryOrEvidencePersisted'] = true,
      (json) => json['requestCount'] = 19,
      (json) => json['responseModelIds'] = ['different-model'],
      (json) => json['sourceFixtureId'] = 'different-fixture',
      (json) => (json['classifier'] as Map)['instrumentDecision'] = 'no_go',
    ]) {
      final json = _instrumentJson();
      mutate(json);
      expect(
        () => Rag3SupportFilterLatencyEvidence.parse(json),
        throwsFormatException,
      );
    }
  });

  test('writes a content-addressed decision artifact once', () async {
    final root = await Directory.systemTemp.createTemp(
      'rag3-support-filter-latency-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/instrument.json');
    final sourceBytes = utf8.encode(jsonEncode(_instrumentJson()));
    await source.writeAsBytes(sourceBytes);
    final options = Rag3SupportFilterLatencyDecisionOptions(
      reportPath: source.path,
      outDir: '${root.path}/out',
    );

    final report = await runRag3SupportFilterLatencyDecision(options);

    expect(report.sourceReportSha256, sha256.convert(sourceBytes).toString());
    expect(
      File(
        '${root.path}/out/rag3_support_filter_latency_decision.json',
      ).existsSync(),
      isTrue,
    );
    await expectLater(
      runRag3SupportFilterLatencyDecision(options),
      throwsStateError,
    );
  });

  test('parses only the exact CLI options', () {
    expect(
      Rag3SupportFilterLatencyDecisionOptions.parse(const [
        '--report',
        'report.json',
        '--out-dir',
        'out',
      ]),
      isNotNull,
    );
    expect(
      Rag3SupportFilterLatencyDecisionOptions.parse(const [
        '--report',
        'report.json',
      ]),
      isNull,
    );
  });
}

Rag3SupportFilterLatencyDecisionReport _decision({required int p95LatencyMs}) =>
    Rag3SupportFilterLatencyDecisionReport(
      sourceReportSha256: List.filled(64, 'a').join(),
      evidence: Rag3SupportFilterLatencyEvidence.parse(
        _instrumentJson(
          p50LatencyMs: p95LatencyMs > 1000 ? 1000 : p95LatencyMs,
          p95LatencyMs: p95LatencyMs,
        ),
      ),
    );

Map<String, Object?> _instrumentJson({
  int p50LatencyMs = 6292,
  int p95LatencyMs = 6464,
  int falsePositive = 0,
}) => {
  'schemaName': 'caverno_rag3_batched_support_filter_instrument',
  'schemaVersion': 1,
  'contract': 'rag3-batched-support-filter-v2',
  'buildCommit': '58da0eb82fc1252d2ca1d814a16dc4adbd47790e',
  'buildDirty': false,
  'sourceFixtureId': 'rag2-compositional-holdout-v1',
  'requestedModelId': 'qwen3.8-27b-vision',
  'responseModelIds': ['qwen3.8-27b-vision'],
  'requestCount': 20,
  'queryOrEvidencePersisted': false,
  'classifierFailureReason': null,
  'productionDecision': 'no_go',
  'promotionDecision': 'not_run',
  'classifier': {
    'schemaName': 'caverno_rag3_batched_support_filter_report',
    'contract': 'rag3-batched-support-filter-v2',
    'fixtureId': 'rag2-compositional-holdout-v1',
    'instrumentDecision': 'go',
    'latencyDecision': 'measurement_only',
    'activationDecision': 'blocked_pending_latency_contract',
    'p50LatencyMs': p50LatencyMs,
    'p95LatencyMs': p95LatencyMs,
    'unavailableCount': 0,
    'invalidCount': 0,
    'metrics': {
      'truePositive': 19,
      'trueNegative': 81 - falsePositive,
      'falsePositive': falsePositive,
      'falseNegative': 0,
    },
  },
};
