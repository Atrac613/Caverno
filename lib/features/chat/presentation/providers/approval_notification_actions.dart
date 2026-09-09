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
  // The button press itself is the one step with no visible trace: the
  // notification disappears whether or not anything acted on it.
  appLog(
    '[ApprovalNotification] action ${action.actionId} for '
    '${action.approvalId}',
  );
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
    appLog(
      '[ApprovalNotification] ${action.approvalId} resolved locally '
      '(approved=${action.isApprove})',
    );
    return;
  }
  final client = ref.read(remoteCodingClientProvider);
  if (client.pendingApproval?.id == action.approvalId) {
    appLog(
      '[ApprovalNotification] ${action.approvalId} sent to the desktop '
      '(approved=${action.isApprove})',
    );
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
  if (client.host != null && !client.isConnected) {
    // The push case. A notification that reached a suspended phone is answered
    // before anything has reconnected, so there is no pending approval here to
    // match against — the socket that would carry one is down. Connect and
    // send the id; the desktop re-checks it against its own pending list and
    // that device's grant, and records a refusal if either has moved on, so
    // sending an id we cannot verify locally resolves nothing we should not.
    appLog(
      '[ApprovalNotification] ${action.approvalId} arrived while '
      'disconnected; reconnecting to answer it',
    );
    unawaited(_resolveAfterReconnect(ref, action));
    return;
  }
  // A stale id fails where it can be seen rather than resolving whatever else
  // happens to be pending.
  appLog(
    '[ApprovalNotification] no pending approval owns '
    '${action.approvalId}; the request was already resolved or withdrawn.',
  );
}

Future<void> _resolveAfterReconnect(
  Ref ref,
  NotificationActionEvent action,
) async {
  final notifier = ref.read(remoteCodingClientProvider.notifier);
  try {
    await notifier.connectSavedHost(automatic: true);
  } catch (error) {
    appLog(
      '[ApprovalNotification] reconnect to answer ${action.approvalId} '
      'failed: $error',
    );
    return;
  }
  if (!ref.read(remoteCodingClientProvider).isConnected) {
    // Say so rather than dropping it. The desktop is still blocked, and the
    // person pressed a button that appeared to do something.
    appLog(
      '[ApprovalNotification] still disconnected; ${action.approvalId} was '
      'not answered. Open Caverno to resolve it.',
    );
    return;
  }
  appLog(
    '[ApprovalNotification] ${action.approvalId} sent to the desktop after '
    'reconnecting (approved=${action.isApprove})',
  );
  await notifier.resolveApproval(
    approvalId: action.approvalId,
    approved: action.isApprove,
  );
}
