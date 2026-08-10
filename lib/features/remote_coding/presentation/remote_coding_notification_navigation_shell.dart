import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/types/workspace_mode.dart';
import '../../chat/presentation/pages/chat_page.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import 'remote_coding_mobile_notification_notifier.dart';
import 'remote_coding_platform.dart';

final class RemoteCodingNotificationNavigationShell
    extends ConsumerStatefulWidget {
  const RemoteCodingNotificationNavigationShell({super.key});

  @override
  ConsumerState<RemoteCodingNotificationNavigationShell> createState() =>
      _RemoteCodingNotificationNavigationShellState();
}

final class _RemoteCodingNotificationNavigationShellState
    extends ConsumerState<RemoteCodingNotificationNavigationShell> {
  final Set<String> _routedEventIds = <String>{};
  var _navigationRevision = 0;
  var _showDashboardOnStartup = true;

  @override
  Widget build(BuildContext context) {
    if (isRemoteCodingMobileRuntimePlatform()) {
      final notificationState = ref.watch(
        remoteCodingMobileNotificationProvider,
      );
      _scheduleNavigation(notificationState);
    }
    return ChatPage(
      key: ValueKey<int>(_navigationRevision),
      showDashboardOnStartup: _showDashboardOnStartup,
    );
  }

  void _scheduleNavigation(RemoteCodingMobileNotificationState state) {
    final notification = state.pendingNotificationTap;
    if (notification == null || !_routedEventIds.add(notification.eventId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            createIfMissing: false,
          );
      setState(() {
        _showDashboardOnStartup = false;
        _navigationRevision += 1;
      });
    });
  }
}
