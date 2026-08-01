import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/presentation/providers/turn_tool_result_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sharedGeneration = 7;
  final ownerA = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: sharedGeneration,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'thread-b',
    interactionGeneration: sharedGeneration,
  );

  ToolResultInfo result(String id) => ToolResultInfo(
    id: id,
    name: 'tool-$id',
    arguments: {'id': id},
    result: 'result-$id',
  );

  test('isolates ordered result and command evidence by composite owner', () {
    final ledger = TurnToolResultLedger();
    final loopA = result('loop-a');
    final contentA = result('content-a');
    final loopB = result('loop-b');
    final contentB = result('content-b');

    ledger
      ..setCompleted(ownerA, [loopA])
      ..addContent(ownerA, contentA)
      ..recordCommand(ownerA, 'command-a')
      ..setCompleted(ownerB, [loopB])
      ..addContent(ownerB, contentB)
      ..recordCommand(ownerB, 'command-b');

    expect(ledger.length, 2);
    expect(ledger.isEmpty, isFalse);
    expect(ledger.completed(ownerA), [loopA]);
    expect(ledger.content(ownerA), [contentA]);
    expect(ledger.commands(ownerA), ['command-a']);
    expect(ledger.all(ownerA), [loopA, contentA]);
    expect(ledger.completed(ownerB), [loopB]);
    expect(ledger.content(ownerB), [contentB]);
    expect(ledger.commands(ownerB), ['command-b']);
    expect(ledger.all(ownerB), [loopB, contentB]);
  });

  test('returns immutable snapshots and searches content newest first', () {
    final ledger = TurnToolResultLedger();
    final originalCompleted = <ToolResultInfo>[result('loop')];
    final first = result('first');
    final second = result('second');
    ledger
      ..setCompleted(ownerA, originalCompleted)
      ..addContent(ownerA, first)
      ..addContent(ownerA, second)
      ..recordCommand(ownerA, 'command');
    originalCompleted.add(result('late'));

    expect(ledger.completed(ownerA), hasLength(1));
    expect(ledger.lastContentResultWhere(ownerA, (_) => true), same(second));
    expect(
      ledger.lastContentResultWhere(ownerA, (item) => item.id == 'missing'),
      isNull,
    );
    expect(ledger.lastContentResultWhere(ownerB, (_) => true), isNull);
    ledger
      ..recordContent(
        ownerA,
        ToolCallInfo(id: 'json-ok', name: 'json', arguments: {}),
        '{"value":1}',
      )
      ..recordContent(
        ownerA,
        ToolCallInfo(id: 'json-error', name: 'json', arguments: {}),
        '{"error":"failed"}',
      )
      ..recordContent(
        ownerA,
        ToolCallInfo(id: 'coded-error', name: 'json', arguments: {}),
        '{"error":"failed","code":"tool_error"}',
      )
      ..recordContent(
        ownerA,
        ToolCallInfo(id: 'plain', name: 'json', arguments: {}),
        'not-json',
      );
    expect(
      ledger
          .lastSuccessfulContentWhere(ownerA, (item) => item.id == 'json-ok')
          ?.id,
      'json-ok',
    );
    expect(
      ledger.lastSuccessfulContentWhere(
        ownerA,
        (item) => item.id == 'json-error',
      ),
      isNull,
    );
    expect(
      ledger.lastSuccessfulContentWhere(
        ownerA,
        (item) => item.id == 'coded-error',
      ),
      isNull,
    );
    expect(
      ledger
          .lastSuccessfulContentWhere(ownerA, (item) => item.id == 'plain')
          ?.id,
      'plain',
    );
    expect(
      () => ledger.completed(ownerA).add(result('blocked')),
      throwsUnsupportedError,
    );
    expect(
      () => ledger.content(ownerA).add(result('blocked')),
      throwsUnsupportedError,
    );
    expect(
      () => ledger.commands(ownerA).add('blocked'),
      throwsUnsupportedError,
    );
    expect(
      () => ledger.all(ownerA).add(result('blocked')),
      throwsUnsupportedError,
    );
  });

  test('clear and take affect only the exact owner', () {
    final ledger = TurnToolResultLedger();
    final loopA = result('loop-a');
    final contentA = result('content-a');
    final loopB = result('loop-b');
    final contentB = result('content-b');
    ledger
      ..setCompleted(ownerA, [loopA])
      ..addContent(ownerA, contentA)
      ..recordCommand(ownerA, 'command-a')
      ..setCompleted(ownerB, [loopB])
      ..addContent(ownerB, contentB)
      ..recordCommand(ownerB, 'command-b');

    ledger.clearContentResults(ownerA);
    expect(ledger.completed(ownerA), [loopA]);
    expect(ledger.content(ownerA), isEmpty);
    expect(ledger.commands(ownerA), ['command-a']);
    expect(ledger.all(ownerB), [loopB, contentB]);

    ledger.addContent(ownerA, contentA);
    final takenA = ledger.takeAll(ownerA);
    expect(takenA, [loopA, contentA]);
    expect(() => takenA.add(result('blocked')), throwsUnsupportedError);
    expect(ledger.completed(ownerA), isEmpty);
    expect(ledger.content(ownerA), isEmpty);
    expect(ledger.commands(ownerA), ['command-a']);
    expect(ledger.all(ownerB), [loopB, contentB]);

    ledger.clearResults(ownerB);
    expect(ledger.completed(ownerB), isEmpty);
    expect(ledger.content(ownerB), isEmpty);
    expect(ledger.commands(ownerB), ['command-b']);
    expect(ledger.takeAndDispose(ownerB), isEmpty);
    expect(ledger.commands(ownerB), isEmpty);
    expect(ledger.length, 1);
  });

  test('repair re-entry preserves owner commands while replacing results', () {
    final ledger = TurnToolResultLedger();

    ledger
      ..recordCommand(ownerA, 'first-command')
      ..setCompleted(ownerA, [result('before-repair')])
      ..recordCommand(ownerA, 'repair-command')
      ..setCompleted(ownerA, [result('after-repair')]);

    expect(ledger.commands(ownerA), ['first-command', 'repair-command']);
    expect(ledger.completed(ownerA).map((item) => item.id), ['after-repair']);
  });

  test('a later owner cannot discard earlier owner evidence', () {
    final ledger = TurnToolResultLedger();
    final newerOwnerA = ChatTurnOwner(
      conversationId: ownerA.conversationId,
      interactionGeneration: sharedGeneration + 1,
    );
    ledger
      ..setCompleted(ownerA, [result('old-a')])
      ..recordCommand(ownerA, 'old-command-a')
      ..setCompleted(newerOwnerA, [result('new-a')])
      ..recordCommand(newerOwnerA, 'new-command-a')
      ..setCompleted(ownerB, [result('current-b')])
      ..recordCommand(ownerB, 'current-command-b');

    expect(ledger.length, 3);
    expect(ledger.completed(ownerA).single.id, 'old-a');
    expect(ledger.commands(ownerA), ['old-command-a']);
    expect(ledger.completed(newerOwnerA).single.id, 'new-a');
    expect(ledger.commands(newerOwnerA), ['new-command-a']);
    expect(ledger.completed(ownerB).single.id, 'current-b');
    expect(ledger.commands(ownerB), ['current-command-b']);

    expect(ledger.takeAndDispose(newerOwnerA).single.id, 'new-a');
    expect(ledger.length, 2);
    expect(ledger.completed(ownerA).single.id, 'old-a');
    expect(ledger.completed(ownerB).single.id, 'current-b');
  });

  test('terminal retention never expires active or foreign evidence', () {
    var current = DateTime(2026, 7, 28);
    final ledger = TurnToolResultLedger(
      retention: const Duration(minutes: 1),
      now: () => current,
    );
    ledger
      ..setCompleted(ownerA, [result('older')])
      ..recordCommand(ownerA, 'older-command');
    current = current.add(const Duration(minutes: 2));
    expect(ledger.completed(ownerA).single.id, 'older');
    ledger.publish(ownerA);
    current = current.add(const Duration(seconds: 30));
    ledger.setCompleted(ownerB, [result('live')]);

    expect(ledger.length, 2);
    current = current.add(const Duration(seconds: 31));
    expect(ledger.completed(ownerA), isEmpty);
    expect(ledger.commands(ownerA), isEmpty);
    expect(ledger.completed(ownerB).single.id, 'live');
    expect(ledger.length, 1);
    current = current.add(const Duration(minutes: 2));
    expect(ledger.completed(ownerB).single.id, 'live');
    ledger
      ..publish(ownerB)
      ..publish(ownerA);
    current = current.add(const Duration(minutes: 1, seconds: 1));
    expect(ledger.isEmpty, isTrue);
  });

  test('missing-owner operations stay empty and disposal is exact', () {
    final ledger = TurnToolResultLedger();
    ledger
      ..setCompleted(ownerA, [result('loop-a')])
      ..addContent(ownerA, result('content-a'))
      ..recordCommand(ownerA, 'command-a');

    expect(ledger.completed(ownerB), isEmpty);
    expect(ledger.content(ownerB), isEmpty);
    expect(ledger.commands(ownerB), isEmpty);
    expect(ledger.all(ownerB), isEmpty);
    final missingSnapshot = ledger.takeAll(ownerB);
    expect(missingSnapshot, isEmpty);
    expect(
      () => missingSnapshot.add(result('blocked')),
      throwsUnsupportedError,
    );
    ledger
      ..clearResults(ownerB)
      ..clearContentResults(ownerB);
    expect(ledger.length, 1);

    expect(ledger.dispose(ownerB), isFalse);
    expect(ledger.dispose(ownerA), isTrue);
    expect(ledger.isEmpty, isTrue);
    expect(ledger.length, 0);
    expect(ledger.completed(ownerA), isEmpty);
    expect(ledger.content(ownerA), isEmpty);
    expect(ledger.commands(ownerA), isEmpty);
    expect(ledger.all(ownerA), isEmpty);
    expect(
      () => ledger.completed(ownerA).add(result('blocked')),
      throwsUnsupportedError,
    );
    expect(
      () => ledger.content(ownerA).add(result('blocked')),
      throwsUnsupportedError,
    );
    expect(
      () => ledger.commands(ownerA).add('blocked'),
      throwsUnsupportedError,
    );
    expect(
      () => ledger.all(ownerA).add(result('blocked')),
      throwsUnsupportedError,
    );
    ledger
      ..setCompleted(ownerA, [result('clear-a')])
      ..setCompleted(ownerB, [result('clear-b')])
      ..clear();
    expect(ledger.isEmpty, isTrue);
  });
}
