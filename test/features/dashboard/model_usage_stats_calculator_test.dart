import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:caverno/features/dashboard/domain/services/model_usage_stats_calculator.dart';

void main() {
  ModelUsageDailyRow row({
    int dayNumber = 20000,
    String model = 'model-a',
    String endpointId = 'primary',
    ModelUsageRole role = ModelUsageRole.chat,
    String label = '',
    int requestCount = 1,
    int errorCount = 0,
    int truncatedCount = 0,
    int durationMs = 1000,
    int promptTokens = 100,
    int completionTokens = 20,
    int totalTokens = 120,
    int cachedPromptTokens = 0,
    int reasoningTokens = 0,
  }) => ModelUsageDailyRow(
    dayNumber: dayNumber,
    model: model,
    endpointId: endpointId,
    role: role.name,
    label: label,
    requestCount: requestCount,
    errorCount: errorCount,
    truncatedCount: truncatedCount,
    durationMs: durationMs,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: totalTokens,
    cachedPromptTokens: cachedPromptTokens,
    audioPromptTokens: 0,
    reasoningTokens: reasoningTokens,
    audioCompletionTokens: 0,
    acceptedPredictionTokens: 0,
    rejectedPredictionTokens: 0,
  );

  test('returns the empty stats for no rows', () {
    final stats = ModelUsageStatsCalculator.compute(const []);
    expect(stats.isEmpty, isTrue);
    expect(stats.totalTokens, 0);
    expect(stats.cacheHitRate, isNull);
  });

  test('sums a model across days and roles', () {
    final stats = ModelUsageStatsCalculator.compute([
      row(dayNumber: 20000),
      row(dayNumber: 20001),
      row(dayNumber: 20001, role: ModelUsageRole.planning),
    ]);

    expect(stats.models, hasLength(1));
    expect(stats.models.single.requestCount, 3);
    expect(stats.models.single.totalTokens, 360);
    expect(stats.roles, hasLength(2));
  });

  test('keeps the same model on two endpoints apart', () {
    final stats = ModelUsageStatsCalculator.compute([
      row(endpointId: 'primary'),
      row(endpointId: 'lan-mesh', totalTokens: 500),
    ]);

    expect(stats.models, hasLength(2));
    expect(stats.models.map((entry) => entry.endpointId).toSet(), {
      'primary',
      'lan-mesh',
    });
  });

  test('orders models by tokens, largest first', () {
    final stats = ModelUsageStatsCalculator.compute([
      row(model: 'small', totalTokens: 10),
      row(model: 'large', totalTokens: 900),
      row(model: 'medium', totalTokens: 100),
    ]);

    expect(stats.models.map((entry) => entry.label), [
      'large',
      'medium',
      'small',
    ]);
  });

  test('shares sum to one across models', () {
    final stats = ModelUsageStatsCalculator.compute([
      row(model: 'a', totalTokens: 300),
      row(model: 'b', totalTokens: 100),
    ]);

    final total = stats.models
        .map(stats.shareOf)
        .fold<double>(0, (sum, share) => sum + share);
    expect(total, closeTo(1.0, 1e-9));
    expect(stats.shareOf(stats.models.first), closeTo(0.75, 1e-9));
  });

  test('reports cache hit rate only when the provider reported one', () {
    final withoutCache = ModelUsageStatsCalculator.compute([row()]);
    expect(withoutCache.cacheHitRate, isNull);

    final withCache = ModelUsageStatsCalculator.compute([
      row(promptTokens: 100, cachedPromptTokens: 90),
    ]);
    expect(withCache.cacheHitRate, closeTo(0.9, 1e-9));
  });

  test('derives average latency and truncation rate', () {
    final stats = ModelUsageStatsCalculator.compute([
      row(requestCount: 4, durationMs: 8000, truncatedCount: 1),
    ]);

    final entry = stats.models.single;
    expect(entry.averageLatencyMs, 2000);
    expect(entry.truncationRate, closeTo(0.25, 1e-9));
  });

  test('breaks out named recovery labels but not the plain main loop', () {
    final stats = ModelUsageStatsCalculator.compute([
      row(),
      row(label: 'tool-loop exhaustion recovery', totalTokens: 400),
    ]);

    final key = stats.models.single.key;
    expect(stats.labelsByModelKey[key], hasLength(1));
    expect(
      stats.labelsByModelKey[key]!.single.label,
      'tool-loop exhaustion recovery',
    );
  });

  test('flags an unattributed role so a missed call site is visible', () {
    final attributed = ModelUsageStatsCalculator.compute([row()]);
    expect(attributed.hasUnattributedRole, isFalse);

    final missed = ModelUsageStatsCalculator.compute([
      row(role: ModelUsageRole.unknown),
    ]);
    expect(missed.hasUnattributedRole, isTrue);
  });

  test('orders daily slices chronologically', () {
    final stats = ModelUsageStatsCalculator.compute([
      row(dayNumber: 20005),
      row(dayNumber: 20001),
      row(dayNumber: 20003),
    ]);

    expect(stats.daily.map((slice) => slice.dayNumber), [20001, 20003, 20005]);
  });

  test('round-trips a model key', () {
    final key = ModelUsageStatsCalculator.modelKey(
      model: 'qwen3.6-27b',
      endpointId: 'lan-mesh',
    );
    expect(ModelUsageStatsCalculator.modelNameFromKey(key), 'qwen3.6-27b');
    expect(ModelUsageStatsCalculator.endpointIdFromKey(key), 'lan-mesh');
  });

  test('round-trips a model name containing spaces and punctuation', () {
    // Model ids are provider-supplied and can be almost anything, so the key
    // separator must be something they never contain.
    const model = 'openai/gpt oss:120b (preview)';
    final key = ModelUsageStatsCalculator.modelKey(
      model: model,
      endpointId: 'cloud endpoint',
    );
    expect(ModelUsageStatsCalculator.modelNameFromKey(key), model);
    expect(ModelUsageStatsCalculator.endpointIdFromKey(key), 'cloud endpoint');
  });

  test('an empty endpoint yields an empty endpoint, not the model name', () {
    final key = ModelUsageStatsCalculator.modelKey(
      model: 'local',
      endpointId: '',
    );
    expect(ModelUsageStatsCalculator.modelNameFromKey(key), 'local');
    expect(ModelUsageStatsCalculator.endpointIdFromKey(key), '');
  });

  test('range bounds cover all history only for the all range', () {
    final now = DateTime(2026, 8, 8);
    expect(
      ModelUsageStatsCalculator.lowerBoundDay(DashboardRange.all, now: now),
      isNull,
    );
    expect(
      ModelUsageStatsCalculator.lowerBoundDay(
        DashboardRange.last7Days,
        now: now,
      ),
      modelUsageDayNumber(DateTime(2026, 8, 1)),
    );
    expect(
      ModelUsageStatsCalculator.lowerBoundDay(
        DashboardRange.last30Days,
        now: now,
      ),
      modelUsageDayNumber(DateTime(2026, 7, 9)),
    );
  });
}
