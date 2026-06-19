import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll10_dependency_grounding_live_canary.dart';

void main() {
  test('passes with deterministic fixture responses', () async {
    final result = await buildLl10DependencyGroundingLiveCanary(
      options: const Ll10DependencyGroundingLiveCanaryOptions(
        showHelp: false,
        fixtureResponse: true,
        timeoutSeconds: 1,
      ),
      generatedAt: DateTime.utc(2026, 6, 19),
    );

    expect(result.status, 'ready_for_ll10_live_canary');
    expect(result.isReady, isTrue);
    expect(result.blockedGateIds, isEmpty);
    expect(
      result.toJson()['schemaName'],
      'll10_dependency_grounding_live_canary_summary',
    );
    expect(result.baseline.hallucinatedApiFailure, isTrue);
    expect(result.grounded.hallucinatedApiFailure, isFalse);
    expect(
      result.gates.map((gate) => gate.id),
      containsAll([
        'grounding_payload_lockfile_exact',
        'baseline_reproduces_future_api_failure',
        'grounded_rejects_future_api',
        'hallucinated_api_failures_reduced',
      ]),
    );
    expect(
      result.toMarkdown(),
      contains('LL10 Dependency Grounding Live Canary'),
    );
  });

  test('blocks when grounded response still uses the future API', () async {
    final result = await buildLl10DependencyGroundingLiveCanary(
      options: const Ll10DependencyGroundingLiveCanaryOptions(
        showHelp: false,
        fixtureResponse: true,
        timeoutSeconds: 1,
      ),
      complete: (prompt) async {
        return '{"symbol_exists":true,"decision":"use",'
            '"evidence_source":"latest_upstream_snippet",'
            '"reason":"Still trusts the future API."}';
      },
    );

    expect(result.status, 'blocked');
    expect(result.blockedGateIds, contains('grounded_rejects_future_api'));
    expect(
      result.blockedGateIds,
      contains('hallucinated_api_failures_reduced'),
    );
  });

  test('parses output and fixture options', () {
    final options = Ll10DependencyGroundingLiveCanaryOptions.parse(const [
      '--fixture-response',
      '--out-json',
      'canary.json',
      '--out-md',
      'canary.md',
      '--timeout-seconds',
      '2',
    ]);

    expect(options.fixtureResponse, isTrue);
    expect(options.outJsonPath, 'canary.json');
    expect(options.outMarkdownPath, 'canary.md');
    expect(options.timeoutSeconds, 2);
  });

  test('rejects unknown options', () {
    expect(
      () => Ll10DependencyGroundingLiveCanaryOptions.parse(const ['--wat']),
      throwsFormatException,
    );
  });
}
