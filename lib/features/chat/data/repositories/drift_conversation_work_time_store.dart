import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/conversation_work_time.dart';
import '../datasources/app_database.dart';

/// Drift-backed per-conversation work time accounting.
///
/// Each recorded unit is folded into its (conversation, kind, detail) row with
/// one upsert, the same shape `DriftModelUsageStore` uses for daily usage.
class DriftConversationWorkTimeStore implements ConversationWorkTimeSink {
  DriftConversationWorkTimeStore(
    this._db, {
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Fire-and-forget by contract; [recorded] exposes the write for tests.
  @override
  void record({
    required String conversationId,
    required ConversationWorkKind kind,
    required int durationMs,
    String detail = '',
    bool isError = false,
  }) {
    unawaited(
      recorded(
        conversationId: conversationId,
        kind: kind,
        durationMs: durationMs,
        detail: detail,
        isError: isError,
      ),
    );
  }

  /// [record] with the write surfaced, for tests and callers that want to wait.
  Future<void> recorded({
    required String conversationId,
    required ConversationWorkKind kind,
    required int durationMs,
    String detail = '',
    bool isError = false,
  }) async {
    final id = conversationId.trim();
    if (id.isEmpty) return;
    final duration = durationMs < 0 ? 0 : durationMs;
    final now = _clock().millisecondsSinceEpoch;
    final table = _db.conversationWorkTime;
    try {
      await _db
          .into(table)
          .insert(
            ConversationWorkTimeCompanion.insert(
              conversationId: id,
              kind: kind.name,
              detail: Value(detail.trim()),
              count: const Value(1),
              errorCount: Value(isError ? 1 : 0),
              durationMs: Value(duration),
              updatedAtMs: Value(now),
            ),
            onConflict: DoUpdate(
              (old) => ConversationWorkTimeCompanion.custom(
                count: old.count + const Constant(1),
                errorCount: old.errorCount + Constant(isError ? 1 : 0),
                durationMs: old.durationMs + Constant(duration),
                updatedAtMs: Constant(now),
              ),
              target: [table.conversationId, table.kind, table.detail],
            ),
          );
    } catch (error) {
      appLog('[work-time] failed to record ${kind.name} for $id: $error');
    }
  }

  /// Streams [conversationId]'s summary, re-emitting whenever it changes.
  Stream<ConversationWorkTimeSummary> watchConversation(String conversationId) {
    final query = _db.select(_db.conversationWorkTime)
      ..where((row) => row.conversationId.equals(conversationId));
    return query.watch().map(_summaryOf);
  }

  /// One-shot equivalent of [watchConversation].
  Future<ConversationWorkTimeSummary> readConversation(String conversationId) {
    final query = _db.select(_db.conversationWorkTime)
      ..where((row) => row.conversationId.equals(conversationId));
    return query.get().then(_summaryOf);
  }

  /// Drops [conversationId]'s accounting, for a "reset" action.
  Future<void> clearConversation(String conversationId) => (_db.delete(
    _db.conversationWorkTime,
  )..where((row) => row.conversationId.equals(conversationId))).go();

  static ConversationWorkTimeSummary _summaryOf(
    List<ConversationWorkTimeRow> rows,
  ) => ConversationWorkTimeSummary([
    for (final row in rows)
      if (ConversationWorkKind.fromName(row.kind) case final kind?)
        ConversationWorkTimeEntry(
          kind: kind,
          detail: row.detail,
          count: row.count,
          errorCount: row.errorCount,
          durationMs: row.durationMs,
        ),
  ]);
}
