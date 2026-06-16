import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_discovery.dart';
import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_transport.dart';
import 'package:caverno/features/chat/data/datasources/parallel_slot_executor.dart';

/// Records concurrency and slot usage so tests can assert isolation
/// deterministically: each runner overlaps with the others via a short delay.
class _Tracker {
  int active = 0;
  int peak = 0;
  final Set<int> activeSlots = {};
  bool slotCollision = false;
  final List<int?> assignedOrder = [];
}

SlotCandidateRunner _runner(
  _Tracker tracker,
  String content, {
  bool throws = false,
}) {
  return (idSlot) async {
    tracker.active += 1;
    tracker.peak = max(tracker.peak, tracker.active);
    tracker.assignedOrder.add(idSlot);
    if (idSlot != null && !tracker.activeSlots.add(idSlot)) {
      tracker.slotCollision = true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    tracker.activeSlots.remove(idSlot);
    tracker.active -= 1;
    if (throws) throw StateError('candidate failed');
    return SlotChatResult(
      content: content,
      finishReason: 'stop',
      raw: const {},
    );
  };
}

void main() {
  const executor = ParallelSlotExecutor();

  test('returns empty for no candidates', () async {
    final outcomes = await executor.run(
      candidates: const [],
      inventory: const SlotInventory.unsupported(),
    );
    expect(outcomes, isEmpty);
  });

  test('runs sequentially and unpinned when slots are unsupported', () async {
    final tracker = _Tracker();
    final outcomes = await executor.run(
      candidates: [
        _runner(tracker, 'a'),
        _runner(tracker, 'b'),
        _runner(tracker, 'c'),
      ],
      inventory: const SlotInventory.unsupported(),
    );

    expect(outcomes.map((o) => o.result!.content), ['a', 'b', 'c']);
    expect(outcomes.every((o) => o.assignedSlot == null), isTrue);
    expect(tracker.peak, 1, reason: 'no concurrency without slots');
  });

  test('runs candidates concurrently on distinct slots', () async {
    final tracker = _Tracker();
    final inventory = SlotInventory.fromJson([
      {'id': 0, 'state': 0},
      {'id': 1, 'state': 0},
      {'id': 2, 'state': 0},
    ]);

    final outcomes = await executor.run(
      candidates: [
        _runner(tracker, 'a'),
        _runner(tracker, 'b'),
        _runner(tracker, 'c'),
      ],
      inventory: inventory,
    );

    expect(outcomes.map((o) => o.result!.content), ['a', 'b', 'c']);
    expect(tracker.peak, 3, reason: 'all three run at once');
    expect(tracker.slotCollision, isFalse, reason: 'distinct slot per worker');
    expect(outcomes.map((o) => o.assignedSlot).toSet(), {0, 1, 2});
  });

  test(
    'caps concurrency at the slot count and reuses slots across waves',
    () async {
      final tracker = _Tracker();
      final inventory = SlotInventory.fromJson([
        {'id': 0, 'state': 0},
        {'id': 1, 'state': 0},
      ]);

      final outcomes = await executor.run(
        candidates: [
          _runner(tracker, 'a'),
          _runner(tracker, 'b'),
          _runner(tracker, 'c'),
          _runner(tracker, 'd'),
          _runner(tracker, 'e'),
        ],
        inventory: inventory,
      );

      expect(outcomes.map((o) => o.result!.content), ['a', 'b', 'c', 'd', 'e']);
      expect(tracker.peak, 2, reason: 'two slots => at most two in flight');
      expect(tracker.slotCollision, isFalse);
      // Every candidate ran on one of the two real slots.
      expect(
        outcomes.every((o) => o.assignedSlot == 0 || o.assignedSlot == 1),
        isTrue,
      );
    },
  );

  test(
    'maxConcurrency forces sequential execution pinned to one slot',
    () async {
      final tracker = _Tracker();
      final inventory = SlotInventory.fromJson([
        {'id': 0, 'state': 0},
        {'id': 1, 'state': 0},
        {'id': 2, 'state': 0},
      ]);

      final outcomes = await executor.run(
        candidates: [_runner(tracker, 'a'), _runner(tracker, 'b')],
        inventory: inventory,
        maxConcurrency: 1,
      );

      expect(outcomes.map((o) => o.result!.content), ['a', 'b']);
      expect(tracker.peak, 1);
      expect(outcomes.every((o) => o.assignedSlot == 0), isTrue);
    },
  );

  test('prefers idle slots and excludes busy ones', () async {
    final tracker = _Tracker();
    final inventory = SlotInventory.fromJson([
      {'id': 0, 'state': 1}, // busy
      {'id': 1, 'state': 0}, // idle
    ]);

    final outcomes = await executor.run(
      candidates: [_runner(tracker, 'a'), _runner(tracker, 'b')],
      inventory: inventory,
    );

    // Only slot 1 is idle => sequential, pinned to slot 1.
    expect(tracker.peak, 1);
    expect(outcomes.every((o) => o.assignedSlot == 1), isTrue);
  });

  test('captures a failed candidate without aborting the batch', () async {
    final tracker = _Tracker();
    final inventory = SlotInventory.fromJson([
      {'id': 0, 'state': 0},
      {'id': 1, 'state': 0},
    ]);

    final outcomes = await executor.run(
      candidates: [
        _runner(tracker, 'a'),
        _runner(tracker, 'b', throws: true),
        _runner(tracker, 'c'),
      ],
      inventory: inventory,
    );

    expect(outcomes[0].isSuccess, isTrue);
    expect(outcomes[0].result!.content, 'a');
    expect(outcomes[1].isSuccess, isFalse);
    expect(outcomes[1].error, isA<StateError>());
    expect(outcomes[2].isSuccess, isTrue);
    expect(outcomes[2].result!.content, 'c');
  });
}
