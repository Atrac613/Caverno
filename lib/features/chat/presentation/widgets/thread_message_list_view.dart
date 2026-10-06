import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'thread_scroll_to_bottom_button.dart';

/// The thread's scrolling message list, with the scroll-to-latest button laid
/// over it when [scrollToBottomVisibility] is given.
class ThreadMessageListView extends StatelessWidget {
  const ThreadMessageListView({
    super.key,
    required this.controller,
    required this.onScrollNotification,
    required this.itemCount,
    required this.itemBuilder,
    required this.onScrollToBottom,
    this.scrollToBottomVisibility,
  });

  final ScrollController controller;
  final NotificationListenerCallback<ScrollNotification> onScrollNotification;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback onScrollToBottom;

  /// Null hides the button entirely.
  final ValueListenable<bool>? scrollToBottomVisibility;

  @override
  Widget build(BuildContext context) {
    final visibility = scrollToBottomVisibility;
    return NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListView.builder(
            key: const ValueKey('chat-message-list'),
            controller: controller,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
          if (visibility != null)
            ValueListenableBuilder<bool>(
              valueListenable: visibility,
              builder: (context, visible, child) {
                if (!visible) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: child,
                  ),
                );
              },
              child: ThreadScrollToBottomButton(onPressed: onScrollToBottom),
            ),
        ],
      ),
    );
  }
}
