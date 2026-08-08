import '../../../chat/data/datasources/app_database.dart';
import '../../../chat/domain/entities/model_usage_role.dart';
import '../entities/dashboard_stats.dart';
import '../entities/model_usage_stats.dart';

/// Folds raw daily usage rows into the shape the usage screen renders.
class ModelUsageStatsCalculator {
  ModelUsageStatsCalculator._();

  /// Separator between a model name and its endpoint in a model key. ASCII
  /// unit separator, because a model name may legitimately contain spaces,
  /// slashes, or colons but never a control character.
  static const String keySeparator = '\u001F';

  /// Lower bound day for [range], or null when the range is unbounded.
  static int? lowerBoundDay(DashboardRange range, {DateTime? now}) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final days = switch (range) {
      DashboardRange.all => null,
      DashboardRange.last30Days => 30,
      DashboardRange.last7Days => 7,
    };
    if (days == null) return null;
    return modelUsageDayNumber(
      DateTime(localNow.year, localNow.month, localNow.day - days),
    );
  }

  static String modelKey({required String model, required String endpointId}) =>
      '$model$keySeparator$endpointId';

  static String modelNameFromKey(String key) => key.split(keySeparator).first;

  static String endpointIdFromKey(String key) {
    final parts = key.split(keySeparator);
    return parts.length > 1 ? parts[1] : '';
  }

  static ModelUsageStats compute(List<ModelUsageDailyRow> rows) {
    if (rows.isEmpty) return ModelUsageStats.empty;

    final byModel = <String, ModelUsageEntry>{};
    final byRole = <String, ModelUsageEntry>{};
    final byDay = <int, Map<String, int>>{};
    final byModelLabel = <String, Map<String, ModelUsageEntry>>{};

    for (final row in rows) {
      final key = modelKey(model: row.model, endpointId: row.endpointId);
      final entry = _entryFrom(row, key: key, label: row.model);

      byModel[key] = byModel[key]?.mergeWith(entry) ?? entry;

      final roleEntry = entry.copyWith(
        key: row.role,
        label: row.role,
        endpointId: '',
      );
      byRole[row.role] = byRole[row.role]?.mergeWith(roleEntry) ?? roleEntry;

      final dayTokens = byDay.putIfAbsent(row.dayNumber, () => <String, int>{});
      dayTokens.update(
        key,
        (value) => value + row.totalTokens,
        ifAbsent: () => row.totalTokens,
      );

      // A blank label is the ordinary main-loop request; only the named
      // recovery paths are worth breaking out.
      if (row.label.isNotEmpty) {
        final labels = byModelLabel.putIfAbsent(
          key,
          () => <String, ModelUsageEntry>{},
        );
        final labelEntry = entry.copyWith(key: row.label, label: row.label);
        labels[row.label] =
            labels[row.label]?.mergeWith(labelEntry) ?? labelEntry;
      }
    }

    return ModelUsageStats(
      models: _sortedByTokens(byModel.values),
      roles: _sortedByTokens(byRole.values),
      daily:
          byDay.entries
              .map(
                (entry) => ModelUsageDaySlice(
                  dayNumber: entry.key,
                  tokensByModelKey: Map<String, int>.unmodifiable(entry.value),
                ),
              )
              .toList(growable: false)
            ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber)),
      labelsByModelKey: {
        for (final entry in byModelLabel.entries)
          entry.key: _sortedByTokens(entry.value.values),
      },
    );
  }

  /// Display name for a role key, falling back to the raw key for a value
  /// written by an older build.
  static ModelUsageRole roleFromKey(String key) => ModelUsageRole.fromName(key);

  static List<ModelUsageEntry> _sortedByTokens(
    Iterable<ModelUsageEntry> entries,
  ) {
    final sorted = entries.toList()
      ..sort((a, b) {
        final byTokens = b.totalTokens.compareTo(a.totalTokens);
        return byTokens != 0 ? byTokens : a.label.compareTo(b.label);
      });
    return List<ModelUsageEntry>.unmodifiable(sorted);
  }

  static ModelUsageEntry _entryFrom(
    ModelUsageDailyRow row, {
    required String key,
    required String label,
  }) => ModelUsageEntry(
    key: key,
    label: label,
    endpointId: row.endpointId,
    requestCount: row.requestCount,
    errorCount: row.errorCount,
    truncatedCount: row.truncatedCount,
    durationMs: row.durationMs,
    promptTokens: row.promptTokens,
    completionTokens: row.completionTokens,
    totalTokens: row.totalTokens,
    cachedPromptTokens: row.cachedPromptTokens,
    audioPromptTokens: row.audioPromptTokens,
    reasoningTokens: row.reasoningTokens,
    audioCompletionTokens: row.audioCompletionTokens,
    acceptedPredictionTokens: row.acceptedPredictionTokens,
    rejectedPredictionTokens: row.rejectedPredictionTokens,
  );
}
