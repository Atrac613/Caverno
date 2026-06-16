import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_transport.dart';
import 'package:caverno/features/chat/data/datasources/parallel_slot_executor.dart';

import '../../tool/ll20_parallel_slot_measurement.dart';

SlotChatResult _result({int? idSlot, double? promptMs}) {
  return SlotChatResult(
    content: 'ok',
    finishReason: 'stop',
    idSlot: idSlot,
    timings: promptMs == null
        ? null
        : LlamaCppTimings(promptMs: promptMs, cacheN: 0, promptN: 100),
    raw: const {},
  );
}

void main() {
  test('Ll20CandidateRecord maps a successful outcome', () {
    final record = Ll20CandidateRecord.fromOutcome(
      2,
      SlotCandidateOutcome.success(_result(idSlot: 1, promptMs: 42.0), 1),
    );
    expect(record.index, 2);
    expect(record.ok, isTrue);
    expect(record.assignedSlot, 1);
    expect(record.servedSlot, 1);
    expect(record.promptMs, 42.0);
    expect(record.error, isNull);
  });

  test('Ll20CandidateRecord maps a failed outcome', () {
    final record = Ll20CandidateRecord.fromOutcome(
      0,
      SlotCandidateOutcome.failure(StateError('boom'), 3),
    );
    expect(record.ok, isFalse);
    expect(record.assignedSlot, 3);
    expect(record.servedSlot, isNull);
    expect(record.error, contains('boom'));
  });

  test('summary reports distinct slots, speedup, and schema', () {
    final summary = Ll20MeasurementSummary(
      generatedAt: DateTime.utc(2026, 6, 17, 1, 2, 3),
      baseUrl: 'http://192.168.1.5:1234/v1',
      model: 'local',
      candidateCount: 3,
      inventorySupported: true,
      slotIds: const [0, 1, 2],
      concurrentWallClockMs: 500,
      sequentialWallClockMs: 1400,
      records: [
        Ll20CandidateRecord.fromOutcome(
          0,
          SlotCandidateOutcome.success(_result(idSlot: 0, promptMs: 30.0), 0),
        ),
        Ll20CandidateRecord.fromOutcome(
          1,
          SlotCandidateOutcome.success(_result(idSlot: 1, promptMs: 31.0), 1),
        ),
        Ll20CandidateRecord.fromOutcome(
          2,
          SlotCandidateOutcome.success(_result(idSlot: 2, promptMs: 29.0), 2),
        ),
      ],
    );

    expect(summary.slotCount, 3);
    expect(summary.successCount, 3);
    expect(summary.distinctServedSlots, {0, 1, 2});
    expect(summary.speedup, closeTo(2.8, 0.0001));

    final json = summary.toJson();
    expect(json['schemaName'], 'caverno_ll20_parallel_slot_measurement');
    expect(json['schemaVersion'], 1);
    expect(json['distinctServedSlots'], [0, 1, 2]);
    expect(json['speedup'], closeTo(2.8, 0.0001));

    final markdown = summary.toMarkdown();
    expect(markdown, contains('LL20 Parallel Slot Measurement'));
    expect(markdown, contains('Speedup: `2.80x`'));
  });

  test('summary omits speedup when concurrent timing is zero', () {
    final summary = Ll20MeasurementSummary(
      generatedAt: DateTime.utc(2026, 6, 17),
      baseUrl: 'b',
      model: 'm',
      candidateCount: 1,
      inventorySupported: false,
      slotIds: const [],
      concurrentWallClockMs: 0,
      sequentialWallClockMs: 0,
      records: const [],
    );
    expect(summary.speedup, isNull);
    expect(summary.toJson().containsKey('speedup'), isFalse);
  });
}
