import 'package:caverno/features/maintenance/domain/services/failure_trace_miner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const editStale = FailureSignature(
    terminalCause: 'edit_apply_failed',
    causalStatus: 'tests_failed',
    mechanism: 'stale_old_text',
  );
  const toolMalformed = FailureSignature(
    terminalCause: 'tool_call_invalid',
    causalStatus: 'no_change',
    mechanism: 'malformed_json',
  );

  FailureTrace trace(
    String caseId,
    FailureSignature sig, [
    String symptom = '',
  ]) => FailureTrace(caseId: caseId, signature: sig, symptom: symptom);

  test('groups traces by signature into clusters', () {
    const miner = FailureTraceMiner();
    final clusters = miner.mine([
      trace('a', editStale, 'old_text not found'),
      trace('b', editStale, 'old_text not found'),
      trace('c', toolMalformed, 'invalid JSON'),
    ]);

    expect(clusters, hasLength(2));
    final edit = clusters.firstWhere((c) => c.signature == editStale);
    expect(edit.support, 2);
    expect(edit.representativeCaseIds(), ['a', 'b']);
    expect(edit.sharedSymptoms, ['old_text not found']);
  });

  test('ranks by support so the biggest weakness comes first', () {
    const miner = FailureTraceMiner();
    final clusters = miner.mine([
      trace('a', editStale),
      trace('b', editStale),
      trace('c', editStale),
      trace('d', toolMalformed),
    ]);

    expect(clusters.first.signature, editStale);
    expect(clusters.first.support, 3);
  });

  test(
    'actionability weight can outrank a larger but less fixable cluster',
    () {
      const miner = FailureTraceMiner(
        actionabilityByMechanism: {
          'stale_old_text': 1.0,
          'malformed_json': 3.0,
        },
      );
      final clusters = miner.mine([
        trace('a', editStale),
        trace('b', editStale), // support 2 x 1.0 = 2.0
        trace('c', toolMalformed), // support 1 x 3.0 = 3.0
      ]);

      expect(clusters.first.signature, toolMalformed);
      expect(clusters.first.score, 3.0);
    },
  );

  test('representative case ids are de-duplicated and capped', () {
    const miner = FailureTraceMiner();
    final clusters = miner.mine([
      trace('a', editStale),
      trace('a', editStale),
      trace('b', editStale),
      trace('c', editStale),
      trace('d', editStale),
    ]);
    expect(clusters.single.representativeCaseIds(limit: 3), ['a', 'b', 'c']);
  });

  test('empty traces yield no clusters', () {
    expect(const FailureTraceMiner().mine(const []), isEmpty);
  });
}
