import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/notification_providers.dart';
import '../../../../core/services/notification_service.dart';
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
  resolveApprovalById(
    ref.read(chatNotifierProvider.notifier),
    id: action.approvalId,
    approved: action.isApprove,
  );
}
