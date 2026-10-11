import 'package:caverno/features/chat/domain/services/tool_loop/content_tool_call_partition.dart';
import 'package:flutter_test/flutter_test.dart';

String tagged(String name) =>
    '<tool_use>{"name":"$name","arguments":{"path":"README.md"}}</tool_use>';

void main() {
  test(
    'preserves order in each partition and accepts every extracted call once',
    () {
      final seen = <String>[];
      final batch = ContentToolCallPartition.fromContent(
        content: ['first', 'second', 'third', 'fourth'].map(tagged).join('\n'),
        advertisedToolNames: {},
        acceptCall: (call) {
          seen.add(call.name);
          expect(call.arguments, {'path': 'README.md'});
          return call.name == 'first' || call.name == 'third';
        },
      );
      expect(seen, ['first', 'second', 'third', 'fourth']);
      expect(batch.fresh.map((call) => call.name), ['first', 'third']);
      expect(batch.repeated.map((call) => call.name), ['second', 'fourth']);
    },
  );
  for (final accepted in [false, true]) {
    test('all calls can be classified together: $accepted', () {
      final batch = ContentToolCallPartition.fromContent(
        content: tagged('one'),
        advertisedToolNames: null,
        acceptCall: (_) => accepted,
      );
      expect(batch.fresh, accepted ? hasLength(1) : isEmpty);
      expect(batch.repeated, accepted ? isEmpty : hasLength(1));
    });
  }
  test('duplicate occurrences are passed independently to acceptance', () {
    var count = 0;
    final batch = ContentToolCallPartition.fromContent(
      content: '${tagged('same')}${tagged('same')}',
      advertisedToolNames: null,
      acceptCall: (_) => ++count == 1,
    );
    expect(count, 2);
    expect(batch.fresh, hasLength(1));
    expect(batch.repeated, hasLength(1));
    expect(
      batch.fresh.single.occurrenceId,
      isNot(batch.repeated.single.occurrenceId),
    );
  });
  for (final advertised in <Set<String>?>[
    null,
    {},
    {'other'},
  ]) {
    test('unoffered raw calls never reach acceptance: $advertised', () {
      final batch = ContentToolCallPartition.fromContent(
        content: '{"name":"read_file","arguments":{}}',
        advertisedToolNames: advertised,
        acceptCall: (_) => throw StateError('unoffered call'),
      );
      expect(batch.fresh, isEmpty);
      expect(batch.repeated, isEmpty);
    });
  }
  test('one unoffered raw name rejects the entire batch', () {
    final batch = ContentToolCallPartition.fromContent(
      content:
          '{"name":"offered","arguments":{}} {"name":"other","arguments":{}}',
      advertisedToolNames: {'offered'},
      acceptCall: (_) => throw StateError('rejected batch'),
    );
    expect(batch.fresh, isEmpty);
    expect(batch.repeated, isEmpty);
  });
  test('offered raw objects retain extraction order', () {
    final batch = ContentToolCallPartition.fromContent(
      content:
          '{"name":"first","arguments":{}} {"name":"second","arguments":{}}',
      advertisedToolNames: {'first', 'second'},
      acceptCall: (_) => true,
    );
    expect(batch.fresh.map((call) => call.name), ['first', 'second']);
  });
  test(
    'tagged calls take precedence over printed calls and advertisement gating',
    () {
      final batch = ContentToolCallPartition.fromContent(
        content: '${tagged('tagged')} {"name":"printed","arguments":{}}',
        advertisedToolNames: {'printed'},
        acceptCall: (_) => true,
      );
      expect(batch.fresh.map((call) => call.name), ['tagged']);
    },
  );
  test('plain content makes no acceptance calls', () {
    final batch = ContentToolCallPartition.fromContent(
      content: 'An answer.',
      advertisedToolNames: {'one'},
      acceptCall: (_) => throw StateError('no candidate'),
    );
    expect(batch.fresh, isEmpty);
    expect(batch.repeated, isEmpty);
  });
  test('acceptance failure retains propagation', () {
    final failure = StateError('seen-key failure');
    expect(
      () => ContentToolCallPartition.fromContent(
        content: tagged('one'),
        advertisedToolNames: null,
        acceptCall: (_) => throw failure,
      ),
      throwsA(same(failure)),
    );
  });
}
