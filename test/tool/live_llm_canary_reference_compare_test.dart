import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_canary_reference_compare.dart';
import '../../tool/live_llm_canary_reference_report.dart';

void main() {
  test('passes when the candidate has no hard regressions', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-reference-compare-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final reference = _writeReferenceReport(
      directory: directory,
      fileName: 'reference.json',
      label: 'reference',
      entries: [
        _entry(
          surface: 'coding_pm5',
          check: 'PM5 smoke',
          passed: 3,
          total: 3,
          signals: const LiveLlmCanaryReferenceSignals(
            approvalFallbackCount: 3,
            cleanupCancellationCount: 2,
          ),
        ),
        _entry(
          surface: 'chat',
          check: 'chat_live_llm_canary',
          passed: 3,
          total: 3,
        ),
      ],
    );
    final candidate = _writeReferenceReport(
      directory: directory,
      fileName: 'candidate.json',
      label: 'candidate',
      entries: [
        _entry(
          surface: 'coding_pm5',
          check: 'PM5 smoke',
          passed: 3,
          total: 3,
          signals: const LiveLlmCanaryReferenceSignals(
            approvalFallbackCount: 3,
            cleanupCancellationCount: 1,
          ),
        ),
        _entry(
          surface: 'chat',
          check: 'chat_live_llm_canary',
          passed: 3,
          total: 3,
        ),
      ],
    );

    final comparison = await buildLiveLlmCanaryReferenceComparison(
      referenceReport: reference,
      candidateReport: candidate,
      label: 'reference vs candidate',
      generatedAt: DateTime.utc(2026, 5, 23, 1, 2, 3),
    );

    expect(comparison.result, 'passed');
    expect(comparison.hardRegressionCount, 0);
    expect(comparison.watchSignalCount, 0);
    expect(comparison.improvementCount, 1);
    expect(
      comparison.entries
          .singleWhere((entry) => entry.surface == 'coding_pm5')
          .status,
      'improved',
    );
    expect(
      comparison.entries
          .singleWhere((entry) => entry.surface == 'coding_pm5')
          .improvements,
      contains('cleanup cancellations decreased 2->1'),
    );
    expect(
      comparison.toJson()['schemaName'],
      'live_llm_canary_reference_compare',
    );
    expect(comparison.toMarkdown(), contains('Hard regressions: `0`'));
  });

  test('fails when the candidate adds hard regressions', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-reference-compare-fail-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final reference = _writeReferenceReport(
      directory: directory,
      fileName: 'reference.json',
      label: 'reference',
      entries: [
        _entry(surface: 'coding_pm5', check: 'PM5 smoke', passed: 3, total: 3),
        _entry(
          surface: 'chat',
          check: 'chat_live_llm_canary',
          passed: 3,
          total: 3,
        ),
      ],
    );
    final candidate = _writeReferenceReport(
      directory: directory,
      fileName: 'candidate.json',
      label: 'candidate',
      entries: [
        _entry(
          surface: 'coding_pm5',
          check: 'PM5 smoke',
          result: 'failed',
          passed: 2,
          total: 3,
          failed: 1,
          signals: const LiveLlmCanaryReferenceSignals(
            unexpectedWarningCount: 1,
            assistantAuthoredToolBlockCount: 1,
            approvalFallbackCount: 1,
          ),
        ),
      ],
    );

    final comparison = await buildLiveLlmCanaryReferenceComparison(
      referenceReport: reference,
      candidateReport: candidate,
      generatedAt: DateTime.utc(2026, 5, 23),
    );

    expect(comparison.result, 'failed');
    expect(comparison.isSuccessful, isFalse);
    expect(comparison.hardRegressionCount, 5);
    expect(comparison.watchSignalCount, 1);
    final coding = comparison.entries.singleWhere(
      (entry) => entry.surface == 'coding_pm5',
    );
    expect(coding.status, 'regressed');
    expect(
      coding.hardRegressions,
      contains('result regressed from passed to failed'),
    );
    expect(coding.hardRegressions, contains('failed tests increased 0->1'));
    expect(
      coding.hardRegressions,
      contains('unexpected warnings increased 0->1'),
    );
    expect(
      coding.hardRegressions,
      contains('assistant tool blocks increased 0->1'),
    );
    expect(coding.watchSignals, contains('approval fallback increased 0->1'));
    final chat = comparison.entries.singleWhere(
      (entry) => entry.surface == 'chat',
    );
    expect(chat.hardRegressions, contains('missing candidate check'));
  });
}

File _writeReferenceReport({
  required Directory directory,
  required String fileName,
  required String label,
  required List<LiveLlmCanaryReferenceEntry> entries,
}) {
  final report = LiveLlmCanaryReferenceReport(
    schemaName: 'live_llm_canary_reference_report',
    schemaVersion: 1,
    generatedAt: DateTime.utc(2026, 5, 23),
    label: label,
    entries: entries,
  );
  final file = File('${directory.path}/$fileName');
  file.writeAsStringSync(jsonEncode(report.toJson()));
  return file;
}

LiveLlmCanaryReferenceEntry _entry({
  required String surface,
  required String check,
  required int passed,
  required int total,
  String result = 'passed',
  int failed = 0,
  LiveLlmCanaryReferenceSignals signals = const LiveLlmCanaryReferenceSignals(),
}) {
  return LiveLlmCanaryReferenceEntry(
    surface: surface,
    check: check,
    result: result,
    model: 'test-model',
    baseUrl: 'http://127.0.0.1:1234/v1',
    evidencePath: '/tmp/$surface.json',
    passed: passed,
    total: total,
    failed: failed,
    signals: signals,
  );
}
