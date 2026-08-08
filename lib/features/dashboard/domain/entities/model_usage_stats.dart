import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../chat/domain/entities/model_usage_role.dart';

part 'model_usage_stats.freezed.dart';

/// Token accounting for one dimension of the usage table (a model+endpoint, or
/// a role), already summed over the selected range.
///
/// Detail fields are 0 when the provider never reported them, which is why
/// [cacheHitRate] and [averageLatencyMs] return null rather than 0 for
/// "unknown" — a local llama.cpp endpoint must not render as a 0% cache hit
/// rate.
@freezed
abstract class ModelUsageEntry with _$ModelUsageEntry {
  const factory ModelUsageEntry({
    required String key,
    required String label,
    @Default('') String endpointId,
    @Default(0) int requestCount,
    @Default(0) int errorCount,
    @Default(0) int truncatedCount,
    @Default(0) int durationMs,
    @Default(0) int promptTokens,
    @Default(0) int completionTokens,
    @Default(0) int totalTokens,
    @Default(0) int cachedPromptTokens,
    @Default(0) int audioPromptTokens,
    @Default(0) int reasoningTokens,
    @Default(0) int audioCompletionTokens,
    @Default(0) int acceptedPredictionTokens,
    @Default(0) int rejectedPredictionTokens,
  }) = _ModelUsageEntry;

  const ModelUsageEntry._();

  /// Share of cached prompt tokens, or null when the provider reported none.
  double? get cacheHitRate {
    if (promptTokens <= 0 || cachedPromptTokens <= 0) return null;
    return cachedPromptTokens / promptTokens;
  }

  /// Mean request duration, or null when nothing was timed.
  int? get averageLatencyMs {
    if (requestCount <= 0 || durationMs <= 0) return null;
    return durationMs ~/ requestCount;
  }

  /// Share of requests that stopped at the token limit.
  double? get truncationRate {
    if (requestCount <= 0) return null;
    return truncatedCount / requestCount;
  }

  /// Share of tokens spent on output rather than input.
  double? get outputRatio {
    if (totalTokens <= 0) return null;
    return completionTokens / totalTokens;
  }

  ModelUsageEntry mergeWith(ModelUsageEntry other) => copyWith(
    requestCount: requestCount + other.requestCount,
    errorCount: errorCount + other.errorCount,
    truncatedCount: truncatedCount + other.truncatedCount,
    durationMs: durationMs + other.durationMs,
    promptTokens: promptTokens + other.promptTokens,
    completionTokens: completionTokens + other.completionTokens,
    totalTokens: totalTokens + other.totalTokens,
    cachedPromptTokens: cachedPromptTokens + other.cachedPromptTokens,
    audioPromptTokens: audioPromptTokens + other.audioPromptTokens,
    reasoningTokens: reasoningTokens + other.reasoningTokens,
    audioCompletionTokens: audioCompletionTokens + other.audioCompletionTokens,
    acceptedPredictionTokens:
        acceptedPredictionTokens + other.acceptedPredictionTokens,
    rejectedPredictionTokens:
        rejectedPredictionTokens + other.rejectedPredictionTokens,
  );
}

/// Tokens for one local day, split by model key.
@freezed
abstract class ModelUsageDaySlice with _$ModelUsageDaySlice {
  const factory ModelUsageDaySlice({
    required int dayNumber,
    @Default(<String, int>{}) Map<String, int> tokensByModelKey,
  }) = _ModelUsageDaySlice;

  const ModelUsageDaySlice._();

  int get totalTokens =>
      tokensByModelKey.values.fold(0, (sum, value) => sum + value);
}

/// Everything the usage screen renders for the selected range.
@freezed
abstract class ModelUsageStats with _$ModelUsageStats {
  const factory ModelUsageStats({
    @Default(<ModelUsageEntry>[]) List<ModelUsageEntry> models,
    @Default(<ModelUsageEntry>[]) List<ModelUsageEntry> roles,
    @Default(<ModelUsageDaySlice>[]) List<ModelUsageDaySlice> daily,
    @Default(<String, List<ModelUsageEntry>>{})
    Map<String, List<ModelUsageEntry>> labelsByModelKey,
  }) = _ModelUsageStats;

  const ModelUsageStats._();

  static const ModelUsageStats empty = ModelUsageStats();

  bool get isEmpty => models.isEmpty;

  int get totalTokens =>
      models.fold(0, (sum, entry) => sum + entry.totalTokens);

  int get totalPromptTokens =>
      models.fold(0, (sum, entry) => sum + entry.promptTokens);

  int get totalCompletionTokens =>
      models.fold(0, (sum, entry) => sum + entry.completionTokens);

  int get totalCachedPromptTokens =>
      models.fold(0, (sum, entry) => sum + entry.cachedPromptTokens);

  int get totalReasoningTokens =>
      models.fold(0, (sum, entry) => sum + entry.reasoningTokens);

  int get totalRequestCount =>
      models.fold(0, (sum, entry) => sum + entry.requestCount);

  /// Overall share of prompt tokens served from cache, or null when no
  /// provider in range reported cache details.
  double? get cacheHitRate {
    if (totalPromptTokens <= 0 || totalCachedPromptTokens <= 0) return null;
    return totalCachedPromptTokens / totalPromptTokens;
  }

  /// Share of the range's tokens attributable to [entry].
  double shareOf(ModelUsageEntry entry) {
    final total = totalTokens;
    return total <= 0 ? 0 : entry.totalTokens / total;
  }

  /// True when some request never claimed a role, meaning a call site was
  /// missed rather than that the user ran an "unknown" feature.
  bool get hasUnattributedRole =>
      roles.any((role) => role.key == ModelUsageRole.unknown.name);
}
