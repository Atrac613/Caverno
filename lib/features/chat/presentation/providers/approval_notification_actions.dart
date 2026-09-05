import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/notification_providers.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../remote_coding/presentation/remote_coding_client_notifier.dart';
import 'chat_notifier.dart';
import 'pending_approval_resolution.dart';

/// Applies Approve/Deny chosen straight from a notification.
///
/// This is the path that works when no Caverno UI is on screen: the phone's
/// lock screen, the notification centre, and — because iOS forwards a
/// notification's actions to a paired Apple Watch automatically — the wrist,
/// with no watchOS code involved. It is the fallback for when the watch
/// companion app itself is not running.
///
/// Read once at app start so the subscription outlives any particular screen.
final approvalNotificationActionsProvider = Provider<void>((ref) {
  final subscription = ref
      .read(notificationServiceProvider)
      .notificationActions
      .listen((action) => _apply(ref, action));
  ref.onDispose(subscription.cancel);
});

void _apply(Ref ref, NotificationActionEvent action) {
  if (!action.isApprove && !action.isDeny) return;
  // Resolution is by approval id, never by thread: a second approval can queue
  // behind the first while the notification is still on screen, and answering
  // "whatever that thread is waiting on" would then land on the wrong command.
  //
  // The id also decides *which* notifier owns the request. Two of them raise
  // this notification now — `ChatNotifier` for a local turn and the Remote
  // Coding client for a blocked desktop one — and resolving a remote id
  // against the chat notifier silently resolved nothing at all.
  if (resolveApprovalById(
    ref.read(chatNotifierProvider.notifier),
    id: action.approvalId,
    approved: action.isApprove,
  )) {
    return;
  }
  final client = ref.read(remoteCodingClientProvider);
  if (client.pendingApproval?.id == action.approvalId) {
    unawaited(
      ref
          .read(remoteCodingClientProvider.notifier)
          .resolveApproval(
            approvalId: action.approvalId,
            approved: action.isApprove,
          ),
    );
    return;
  }
  // A stale id fails where it can be seen rather than resolving whatever else
  // happens to be pending.
  appLog(
    '[ApprovalNotification] no pending approval owns '
    '${action.approvalId}; the request was already resolved or withdrawn.',
  );
}
