import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/drift_model_usage_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_completion_terminal_metadata.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late DriftModelUsageStore store;

  setUp(() {
    db = AppDatabase.memory();
    now = DateTime(2026, 8, 8, 12);
    store = DriftModelUsageStore(db, clock: () => now);
  });

  tearDown(() async => db.close());

  const usage = TokenUsage(
    promptTokens: 100,
    completionTokens: 20,
    totalTokens: 120,
    cachedPromptTokens: 80,
    reasoningTokens: 5,
  );

  Future<void> record({
    String model = 'model-a',
    String endpointId = 'primary',
    ModelUsageRole role = ModelUsageRole.chat,
    String label = '',
    TokenUsage tokens = usage,
    int durationMs = 1000,
    String? finishReason,
    bool isError = false,
  }) {
    return store.recorded(
      model: model,
      endpointId: endpointId,
      role: role,
      label: label,
      usage: tokens,
      durationMs: durationMs,
      finishReason: finishReason,
      isError: isError,
    );
  }

  test('folds repeated requests into one row, summing every column', () async {
    await record();
    await record();
    await record();

    final rows = await store.readRows();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.requestCount, 3);
    expect(row.promptTokens, 300);
    expect(row.completionTokens, 60);
    expect(row.totalTokens, 360);
    expect(row.cachedPromptTokens, 240);
    expect(row.reasoningTokens, 15);
    expect(row.durationMs, 3000);
  });

  test('keeps the same model on two endpoints as separate rows', () async {
    await record(endpointId: 'primary');
    await record(endpointId: 'lan-mesh');

    final rows = await store.readRows();
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.endpointId).toSet(), {'primary', 'lan-mesh'});
  });

  test('separates rows across every key dimension', () async {
    await record();
    await record(model: 'model-b');
    await record(role: ModelUsageRole.memoryExtraction);
    await record(label: 'tool-loop exhaustion recovery');

    final rows = await store.readRows();
    expect(rows, hasLength(4));
  });

  test('counts length-truncated completions separately', () async {
    await record(finishReason: 'stop');
    await record(finishReason: 'length');
    await record(finishReason: 'length');

    final row = (await store.readRows()).single;
    expect(row.requestCount, 3);
    expect(row.truncatedCount, 2);
  });

  test('counts errors and still records them without usage', () async {
    await record(tokens: TokenUsage.zero, isError: true);

    final row = (await store.readRows()).single;
    expect(row.requestCount, 1);
    expect(row.errorCount, 1);
    expect(row.totalTokens, 0);
  });

  test('skips requests that report no usage', () async {
    await record(tokens: TokenUsage.zero);
    expect(await store.readRows(), isEmpty);
  });

  test('skips requests with a blank model', () async {
    await record(model: '   ');
    expect(await store.readRows(), isEmpty);
  });

  test('buckets requests either side of local midnight separately', () async {
    now = DateTime(2026, 8, 8, 23, 59);
    await record();
    now = DateTime(2026, 8, 9, 0, 1);
    await record();

    final rows = await store.readRows();
    expect(rows, hasLength(2));
    expect(
      rows.map((row) => row.dayNumber).toSet().length,
      2,
      reason: 'a request at 23:59 and one at 00:01 are different days',
    );
  });

  test('filters rows by day lower bound', () async {
    now = DateTime(2026, 8, 1, 12);
    await record();
    now = DateTime(2026, 8, 8, 12);
    await record();

    final cutoff = modelUsageDayNumber(DateTime(2026, 8, 5));
    final rows = await store.readRows(fromDayNumber: cutoff);
    expect(rows, hasLength(1));
    expect(rows.single.dayNumber, modelUsageDayNumber(DateTime(2026, 8, 8)));
  });

  test('clear drops all accounting', () async {
    await record();
    await store.clear();
    expect(await store.readRows(), isEmpty);
  });
}
