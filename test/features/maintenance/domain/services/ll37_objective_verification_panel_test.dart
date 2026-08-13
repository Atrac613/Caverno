import 'dart:convert';

import 'package:caverno/features/maintenance/domain/services/ll37_objective_verification_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const candidate = Ll37ObjectiveCandidate(
    id: 'routine-1',
    sourceSurface: Ll37ObjectiveSourceSurface.routine,
    attended: false,
    ll34OutcomeSettled: false,
    objective: 'Set the feature flag to true.',
    acceptanceCriteria: ['settings.json contains featureEnabled true.'],
    plan: 'Update only settings.json.',
    changedFiles: [
      Ll37ObjectiveChangedFile(
        path: 'settings.json',
        content: '{"featureEnabled":true}',
      ),
    ],
    implementationEvidence: ['syntax verification exited 0'],
  );

  test('evaluates one candidate with one bounded tool-free request', () async {
    var calls = 0;
    late String capturedPrompt;
    late int capturedMaxTokens;
    final panel = Ll37ObjectiveVerificationPanel(
      maxOutputTokens: 321,
      complete: (prompt, maxOutputTokens) async {
        calls += 1;
        capturedPrompt = prompt;
        capturedMaxTokens = maxOutputTokens;
        return jsonEncode({
          'verdict': 'not_refuted',
          'confidence': 0.9,
          'blocking': 'none',
          'findings': [],
        });
      },
    );

    final report = await panel.evaluate(
      candidate: candidate,
      isCancelled: () => false,
    );

    expect(calls, 1);
    expect(capturedMaxTokens, 321);
    expect(capturedPrompt, contains('Do not call tools'));
    expect(capturedPrompt, contains('settings.json'));
    expect(report.status, Ll37ObjectivePanelStatus.evaluated);
    expect(report.requestCount, 1);
    expect(report.verdict?.verdict, Ll37ObjectiveVerdict.notRefuted);
    expect(report.verdict?.confidence, 0.9);
    expect(report.estimatedInputTokens, greaterThan(0));
    expect(report.estimatedOutputTokens, greaterThan(0));
    expect(
      report.estimatedTotalTokens,
      report.estimatedInputTokens + report.estimatedOutputTokens,
    );
  });

  test(
    'skips attended and LL34-settled candidates without a request',
    () async {
      var calls = 0;
      final panel = Ll37ObjectiveVerificationPanel(
        complete: (_, _) async {
          calls += 1;
          return '{}';
        },
      );

      final attended = await panel.evaluate(
        candidate: _copyCandidate(candidate, attended: true),
        isCancelled: () => false,
      );
      final settled = await panel.evaluate(
        candidate: _copyCandidate(candidate, ll34OutcomeSettled: true),
        isCancelled: () => false,
      );

      expect(calls, 0);
      expect(attended.status, Ll37ObjectivePanelStatus.skipped);
      expect(attended.detail, contains('attended'));
      expect(settled.status, Ll37ObjectivePanelStatus.skipped);
      expect(settled.detail, contains('LL34'));
    },
  );

  test('honors cancellation before and after the only request', () async {
    var calls = 0;
    var cancelled = true;
    final panel = Ll37ObjectiveVerificationPanel(
      complete: (_, _) async {
        calls += 1;
        cancelled = true;
        return jsonEncode({
          'verdict': 'not_refuted',
          'confidence': 1,
          'blocking': 'none',
          'findings': [],
        });
      },
    );

    final before = await panel.evaluate(
      candidate: candidate,
      isCancelled: () => cancelled,
    );
    cancelled = false;
    final during = await panel.evaluate(
      candidate: candidate,
      isCancelled: () => cancelled,
    );

    expect(before.status, Ll37ObjectivePanelStatus.cancelled);
    expect(before.requestCount, 0);
    expect(during.status, Ll37ObjectivePanelStatus.cancelled);
    expect(during.requestCount, 1);
    expect(calls, 1);
  });

  test('skips oversized or incomplete evidence', () async {
    var calls = 0;
    final panel = Ll37ObjectiveVerificationPanel(
      maxPromptCharacters: 100,
      complete: (_, _) async {
        calls += 1;
        return '{}';
      },
    );

    final oversized = await panel.evaluate(
      candidate: candidate,
      isCancelled: () => false,
    );
    final incomplete = await panel.evaluate(
      candidate: _copyCandidate(candidate, objective: ''),
      isCancelled: () => false,
    );

    expect(calls, 0);
    expect(oversized.status, Ll37ObjectivePanelStatus.skipped);
    expect(oversized.detail, contains('prompt-size'));
    expect(incomplete.status, Ll37ObjectivePanelStatus.skipped);
    expect(incomplete.detail, contains('incomplete'));
  });

  test('maps invalid output and transport failures to unverifiable', () async {
    final invalidPanel = Ll37ObjectiveVerificationPanel(
      complete: (_, _) async => jsonEncode({
        'verdict': 'refuted',
        'confidence': 2,
        'blocking': 'none',
        'findings': [],
      }),
    );
    final failedPanel = Ll37ObjectiveVerificationPanel(
      complete: (_, _) async => throw StateError('endpoint offline'),
    );

    final invalid = await invalidPanel.evaluate(
      candidate: candidate,
      isCancelled: () => false,
    );
    final failed = await failedPanel.evaluate(
      candidate: candidate,
      isCancelled: () => false,
    );

    expect(invalid.verdict?.verdict, Ll37ObjectiveVerdict.unverifiable);
    expect(invalid.verdict?.blocking, Ll37ObjectiveBlocking.unverifiable);
    expect(invalid.verdict?.error, isNotEmpty);
    expect(failed.status, Ll37ObjectivePanelStatus.evaluated);
    expect(failed.requestCount, 1);
    expect(failed.verdict?.verdict, Ll37ObjectiveVerdict.unverifiable);
    expect(failed.verdict?.error, contains('endpoint offline'));
  });

  test(
    'skips a failed route precondition without counting a request',
    () async {
      final panel = Ll37ObjectiveVerificationPanel(
        complete: (_, _) async =>
            throw const Ll37ObjectiveVerifierPreconditionException(
              'verifier route is no longer eligible',
            ),
      );

      final report = await panel.evaluate(
        candidate: candidate,
        isCancelled: () => false,
      );

      expect(report.status, Ll37ObjectivePanelStatus.skipped);
      expect(report.requestCount, 0);
      expect(report.verdict, isNull);
      expect(report.detail, contains('no longer eligible'));
    },
  );

  test('requires concrete findings for a refutation', () async {
    final panel = Ll37ObjectiveVerificationPanel(
      complete: (_, _) async => jsonEncode({
        'verdict': 'refuted',
        'confidence': 1,
        'blocking': 'contradiction',
        'findings': [
          {
            'kind': 'unmet_criterion',
            'location': 'settings.json',
            'detail': 'featureEnabled remains false',
          },
        ],
      }),
    );

    final report = await panel.evaluate(
      candidate: candidate,
      isCancelled: () => false,
    );

    expect(report.verdict?.verdict, Ll37ObjectiveVerdict.refuted);
    expect(report.verdict?.blocking, Ll37ObjectiveBlocking.contradiction);
    expect(report.verdict?.findings.single.location, 'settings.json');
  });

  test('requires unverifiable blocking for an unverifiable verdict', () async {
    final panel = Ll37ObjectiveVerificationPanel(
      complete: (_, _) async => jsonEncode({
        'verdict': 'unverifiable',
        'confidence': 0.5,
        'blocking': 'none',
        'findings': [],
      }),
    );

    final report = await panel.evaluate(
      candidate: candidate,
      isCancelled: () => false,
    );

    expect(report.verdict?.verdict, Ll37ObjectiveVerdict.unverifiable);
    expect(report.verdict?.blocking, Ll37ObjectiveBlocking.unverifiable);
    expect(report.verdict?.error, contains('requires unverifiable blocking'));
  });

  test('requires contradiction blocking for a refuted verdict', () async {
    final panel = Ll37ObjectiveVerificationPanel(
      complete: (_, _) async => jsonEncode({
        'verdict': 'refuted',
        'confidence': 1,
        'blocking': 'none',
        'findings': [
          {
            'kind': 'unmet_criterion',
            'location': 'settings.json',
            'detail': 'featureEnabled remains false',
          },
        ],
      }),
    );

    final report = await panel.evaluate(
      candidate: candidate,
      isCancelled: () => false,
    );

    expect(report.verdict?.verdict, Ll37ObjectiveVerdict.unverifiable);
    expect(report.verdict?.blocking, Ll37ObjectiveBlocking.unverifiable);
    expect(report.verdict?.error, contains('requires contradiction blocking'));
  });
}

Ll37ObjectiveCandidate _copyCandidate(
  Ll37ObjectiveCandidate candidate, {
  bool? attended,
  bool? ll34OutcomeSettled,
  String? objective,
}) {
  return Ll37ObjectiveCandidate(
    id: candidate.id,
    sourceSurface: candidate.sourceSurface,
    attended: attended ?? candidate.attended,
    ll34OutcomeSettled: ll34OutcomeSettled ?? candidate.ll34OutcomeSettled,
    objective: objective ?? candidate.objective,
    acceptanceCriteria: candidate.acceptanceCriteria,
    plan: candidate.plan,
    changedFiles: candidate.changedFiles,
    implementationEvidence: candidate.implementationEvidence,
  );
}
