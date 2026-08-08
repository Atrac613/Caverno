import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/chat_completion_terminal_metadata.dart';
import '../../domain/entities/model_usage_role.dart';
import '../../domain/entities/model_usage_sink.dart';
import '../datasources/app_database.dart';
import '../datasources/llm_session_log_store.dart';

/// Drift-backed per-model token usage accounting.
///
/// Each recorded request is folded into a daily row keyed by
/// (day, model, endpoint, role, label) with a single upsert, so the table stays
/// small and reads are plain aggregations.
class DriftModelUsageStore implements ModelUsageSink {
  DriftModelUsageStore(this._db, {DateTime Function() clock = DateTime.now})
    : _clock = clock;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Completions reported as stopping at the token limit.
  static const String truncatedFinishReason = 'length';

  /// Fire-and-forget by contract: a chat turn must never fail because usage
  /// bookkeeping did. [recorded] exposes the write for tests that need to await
  /// it.
  @override
  void record({
    required String model,
    required String endpointId,
    required ModelUsageRole role,
    required TokenUsage usage,
    required int durationMs,
    String? label,
    String? finishReason,
    bool isError = false,
  }) {
    // Resolved here rather than in the data source, which cannot import the
    // session log store without a cycle. The zone is still the caller's, since
    // record() runs synchronously inside the request.
    final resolvedLabel = label ?? LlmSessionLogContext.current?.requestLabel;
    unawaited(
      recorded(
        model: model,
        endpointId: endpointId,
        role: role,
        label: resolvedLabel ?? '',
        usage: usage,
        durationMs: durationMs,
        finishReason: finishReason,
        isError: isError,
      ),
    );
  }

  /// [record] with the write surfaced, for tests and callers that want to wait.
  Future<void> recorded({
    required String model,
    required String endpointId,
    required ModelUsageRole role,
    required String label,
    required TokenUsage usage,
    required int durationMs,
    String? finishReason,
    bool isError = false,
  }) async {
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) return;
    // Nothing to account for: providers such as Apple Foundation Models report
    // no usage at all, and empty rows would only dilute the breakdown.
    if (usage.totalTokens <= 0 && !isError) return;

    final truncated = finishReason == truncatedFinishReason ? 1 : 0;
    final table = _db.modelUsageDaily;
    try {
      await _db
          .into(table)
          .insert(
            ModelUsageDailyCompanion.insert(
              dayNumber: modelUsageDayNumber(_clock()),
              model: normalizedModel,
              endpointId: Value(endpointId.trim()),
              role: Value(role.name),
              label: Value(label.trim()),
              requestCount: const Value(1),
              errorCount: Value(isError ? 1 : 0),
              truncatedCount: Value(truncated),
              durationMs: Value(durationMs < 0 ? 0 : durationMs),
              promptTokens: Value(usage.promptTokens),
              completionTokens: Value(usage.completionTokens),
              totalTokens: Value(usage.totalTokens),
              cachedPromptTokens: Value(usage.cachedPromptTokens),
              audioPromptTokens: Value(usage.audioPromptTokens),
              reasoningTokens: Value(usage.reasoningTokens),
              audioCompletionTokens: Value(usage.audioCompletionTokens),
              acceptedPredictionTokens: Value(usage.acceptedPredictionTokens),
              rejectedPredictionTokens: Value(usage.rejectedPredictionTokens),
            ),
            onConflict: DoUpdate(
              (old) => ModelUsageDailyCompanion.custom(
                requestCount: old.requestCount + const Constant(1),
                errorCount: old.errorCount + Constant(isError ? 1 : 0),
                truncatedCount: old.truncatedCount + Constant(truncated),
                durationMs:
                    old.durationMs + Constant(durationMs < 0 ? 0 : durationMs),
                promptTokens: old.promptTokens + Constant(usage.promptTokens),
                completionTokens:
                    old.completionTokens + Constant(usage.completionTokens),
                totalTokens: old.totalTokens + Constant(usage.totalTokens),
                cachedPromptTokens:
                    old.cachedPromptTokens + Constant(usage.cachedPromptTokens),
                audioPromptTokens:
                    old.audioPromptTokens + Constant(usage.audioPromptTokens),
                reasoningTokens:
                    old.reasoningTokens + Constant(usage.reasoningTokens),
                audioCompletionTokens:
                    old.audioCompletionTokens +
                    Constant(usage.audioCompletionTokens),
                acceptedPredictionTokens:
                    old.acceptedPredictionTokens +
                    Constant(usage.acceptedPredictionTokens),
                rejectedPredictionTokens:
                    old.rejectedPredictionTokens +
                    Constant(usage.rejectedPredictionTokens),
              ),
              target: [
                table.dayNumber,
                table.model,
                table.endpointId,
                table.role,
                table.label,
              ],
            ),
          );
    } catch (error) {
      appLog(
        '[usage] failed to record model usage for $normalizedModel: $error',
      );
    }
  }

  /// Streams every row on or after [fromDayNumber] (null = all of history),
  /// re-emitting whenever the table changes.
  Stream<List<ModelUsageDailyRow>> watchRows({int? fromDayNumber}) {
    final query = _db.select(_db.modelUsageDaily);
    if (fromDayNumber != null) {
      query.where((row) => row.dayNumber.isBiggerOrEqualValue(fromDayNumber));
    }
    return query.watch();
  }

  /// One-shot equivalent of [watchRows].
  Future<List<ModelUsageDailyRow>> readRows({int? fromDayNumber}) {
    final query = _db.select(_db.modelUsageDaily);
    if (fromDayNumber != null) {
      query.where((row) => row.dayNumber.isBiggerOrEqualValue(fromDayNumber));
    }
    return query.get();
  }

  /// Drops all accounting. Exposed for a "reset statistics" action.
  Future<void> clear() => _db.delete(_db.modelUsageDaily).go();
}
