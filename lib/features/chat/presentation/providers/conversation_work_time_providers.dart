import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/background_process_types.dart';
import '../../domain/entities/conversation_work_time.dart';
import '../../domain/services/approval_wait_ledger.dart';
import 'model_usage_providers.dart';

export 'model_usage_providers.dart' show conversationWorkTimeStoreProvider;

/// The process-wide approval wait ledger, with its sink pointed at this
/// scope's store for as long as the scope lives.
///
/// The ledger itself is shared because the approval registry reaches it
/// without injection (see [ApprovalWaitLedger]); only the sink is scoped.
final approvalWaitLedgerProvider = Provider<ApprovalWaitLedger>((ref) {
  final ledger = ApprovalWaitLedger.shared;
  final store = ref.watch(conversationWorkTimeStoreProvider);
  ledger.sink = store;
  ref.onDispose(() {
    if (identical(ledger.sink, store)) ledger.sink = null;
  });
  return ledger;
});

/// [conversationId]'s recorded work time, live from the database. Empty
/// without drift, where nothing is recorded.
final conversationWorkTimeSummaryProvider = StreamProvider.autoDispose
    .family<ConversationWorkTimeSummary, String>((ref, conversationId) {
      final store = ref.watch(conversationWorkTimeStoreProvider);
      if (store == null) {
        return Stream.value(ConversationWorkTimeSummary.empty);
      }
      return store.watchConversation(conversationId);
    });

/// Books each exited background job as [sink]'s background process time, or
/// null to report nothing when there is no store.
BackgroundProcessFinishedCallback? backgroundJobWorkTimeReporter(
  ConversationWorkTimeSink? sink,
) {
  if (sink == null) return null;
  return ({required conversationId, required elapsedMs, exitCode}) =>
      sink.record(
        conversationId: conversationId,
        kind: ConversationWorkKind.backgroundProcess,
        durationMs: elapsedMs,
        isError: exitCode != 0,
      );
}
