import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Where the user left a thread.
///
/// [atBottom] is tracked apart from [offset] because a thread that keeps
/// streaming while it is off screen grows past the pixel offset that used to be
/// its end: restoring the raw offset would drop the user mid-history when they
/// were in fact following the newest message.
@immutable
class ThreadScrollAnchor {
  const ThreadScrollAnchor({required this.offset, required this.atBottom});

  final double offset;
  final bool atBottom;
}

/// Owns the chat message list's scroll position.
///
/// Two rules share one controller, which is why they share one owner:
///
/// * While a turn streams, the view follows the newest content unless the user
///   scrolled up to read history.
/// * Opening a thread shows its latest state, because seeing where a thread
///   ended up is the reason to reopen it. Reopening a thread already visited in
///   this session restores the position it was left at instead.
///
/// The per-thread positions are deliberately in-memory only: a fresh app launch
/// always starts at the newest message.
class ThreadScrollCoordinator {
  /// How many frames the settle loop may run for.
  ///
  /// `ListView.builder` lays out only the items around the viewport, so
  /// `maxScrollExtent` starts as an estimate extrapolated from the children
  /// built so far. Jumping to that estimate builds more children and pushes the
  /// extent further out, which is why a single post-frame jump lands short of
  /// the real bottom on long threads. Re-jumping for a few frames converges.
  static const int settleFrames = 8;

  /// Tolerance, in logical pixels, for treating two scroll offsets as equal.
  static const double _epsilon = 0.5;

  /// How far from the bottom still counts as following the live stream.
  static const double _bottomThreshold = 80;

  final ScrollController controller = ScrollController();
  final Map<String, ThreadScrollAnchor> _anchors =
      <String, ThreadScrollAnchor>{};

  String? _trackedConversationId;
  bool _isApplyingThreadScroll = false;
  bool _autoFollowBottom = true;
  bool _isScrollToBottomScheduled = false;
  bool _scheduledScrollShouldAnimate = false;
  bool _isDisposed = false;

  void dispose() {
    _isDisposed = true;
    controller.dispose();
  }

  bool get isNearBottom {
    if (!controller.hasClients) {
      return true;
    }
    final position = controller.position;
    return position.maxScrollExtent - position.pixels <= _bottomThreshold;
  }

  /// Tracks deliberate user scrolling so streaming auto-scroll backs off when
  /// the user scrolls up to read history and resumes once they return to the
  /// bottom. Programmatic `animateTo`/`jumpTo` never emit a
  /// [UserScrollNotification], so this reacts only to real gestures and is
  /// therefore immune to the scroll position lagging behind streamed content.
  bool handleScrollNotification(ScrollNotification notification) {
    // Ignore notifications bubbling up from scrollables nested inside messages.
    if (notification.depth != 0) {
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        // Dragging toward older messages: stop following the live stream.
        _autoFollowBottom = false;
      }
    } else if (notification is ScrollEndNotification && !_autoFollowBottom) {
      // Re-engage following once the user settles back near the bottom.
      if (isNearBottom) {
        _autoFollowBottom = true;
      }
    }
    return false;
  }

  void onChatStateChanged(ChatState? previous, ChatState next) {
    if (previous?.messages.length != next.messages.length) {
      // A message was added or removed: snap to the newest entry and resume
      // following the live stream.
      _autoFollowBottom = true;
      scheduleScrollToBottom(animated: true);
      return;
    }
    // Same message count: only react to the last message growing while it
    // streams, and only while the user has not scrolled up to read history.
    if (next.messages.isEmpty || !next.messages.last.isStreaming) {
      return;
    }
    if (!_autoFollowBottom) {
      return;
    }
    scheduleScrollToBottom(animated: false);
  }

  void scheduleScrollToBottom({required bool animated}) {
    _scheduledScrollShouldAnimate = _scheduledScrollShouldAnimate || animated;
    if (_isScrollToBottomScheduled) {
      return;
    }

    _isScrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shouldAnimate = _scheduledScrollShouldAnimate;
      _isScrollToBottomScheduled = false;
      _scheduledScrollShouldAnimate = false;
      scrollToBottom(animated: shouldAnimate);
    });
  }

  void scrollToBottom({bool animated = true}) {
    // While a thread-open scroll settles, it owns the final position.
    if (_isDisposed || _isApplyingThreadScroll || !controller.hasClients) {
      return;
    }
    final target = controller.position.maxScrollExtent;
    if (animated) {
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }
    controller.jumpTo(target);
  }

  /// Applies the thread-open rule. Safe to call from `build`: it only records
  /// the outgoing offset and schedules post-frame scrolling.
  void syncThread({
    required String? conversationId,
    required bool isMessageListVisible,
  }) {
    if (!isMessageListVisible || conversationId == null) {
      // The list is leaving the screen (dashboard, routines, empty thread).
      // Keep its offset so coming back lands in the same place.
      _rememberTrackedAnchor();
      _trackedConversationId = null;
      return;
    }
    if (conversationId == _trackedConversationId) {
      return;
    }
    _rememberTrackedAnchor();
    _trackedConversationId = conversationId;

    final anchor = _anchors[conversationId];
    // Suppress the streaming auto-scroll until this settles, so a restored
    // position is not immediately overwritten by a jump to the bottom.
    _isApplyingThreadScroll = true;
    _scheduleFrame(() {
      if (anchor == null || anchor.atBottom) {
        _settleToBottom(remainingFrames: settleFrames, previousExtent: null);
        return;
      }
      _restoreOffset(offset: anchor.offset, remainingFrames: settleFrames);
    });
  }

  /// Runs [callback] after the current frame.
  ///
  /// Also requests a frame: a hop registered from inside the post-frame phase
  /// would otherwise stay pending until something unrelated schedules one,
  /// leaving the settle loop (and the auto-scroll suppression it holds)
  /// half-finished.
  void _scheduleFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    WidgetsBinding.instance.scheduleFrame();
  }

  void _rememberTrackedAnchor() {
    final trackedId = _trackedConversationId;
    if (trackedId == null || !controller.hasClients) {
      return;
    }
    _anchors[trackedId] = ThreadScrollAnchor(
      offset: controller.offset,
      atBottom: isNearBottom,
    );
  }

  void _settleToBottom({
    required int remainingFrames,
    required double? previousExtent,
  }) {
    if (_isDisposed) {
      _isApplyingThreadScroll = false;
      return;
    }
    if (!controller.hasClients) {
      if (remainingFrames <= 0) {
        _abandon();
        return;
      }
      _scheduleFrame(
        () => _settleToBottom(
          remainingFrames: remainingFrames - 1,
          previousExtent: previousExtent,
        ),
      );
      return;
    }

    final extent = controller.position.maxScrollExtent;
    final atBottom = (controller.offset - extent).abs() <= _epsilon;
    if (!atBottom) {
      controller.jumpTo(extent);
    }
    final extentSettled =
        previousExtent != null && (extent - previousExtent).abs() <= _epsilon;
    if ((atBottom && extentSettled) || remainingFrames <= 0) {
      _autoFollowBottom = true;
      _isApplyingThreadScroll = false;
      return;
    }
    _scheduleFrame(
      () => _settleToBottom(
        remainingFrames: remainingFrames - 1,
        previousExtent: extent,
      ),
    );
  }

  void _restoreOffset({required double offset, required int remainingFrames}) {
    if (_isDisposed) {
      _isApplyingThreadScroll = false;
      return;
    }
    if (!controller.hasClients) {
      if (remainingFrames <= 0) {
        _abandon();
        return;
      }
      _scheduleFrame(
        () => _restoreOffset(
          offset: offset,
          remainingFrames: remainingFrames - 1,
        ),
      );
      return;
    }

    final position = controller.position;
    final target = offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((controller.offset - target).abs() > _epsilon) {
      controller.jumpTo(target);
    }
    // While items are still being built the extent under-reports, so the wanted
    // offset may not be reachable yet; keep re-clamping until it is.
    if ((target - offset).abs() <= _epsilon || remainingFrames <= 0) {
      _autoFollowBottom = isNearBottom;
      _isApplyingThreadScroll = false;
      return;
    }
    _scheduleFrame(
      () =>
          _restoreOffset(offset: offset, remainingFrames: remainingFrames - 1),
    );
  }

  /// Releases the thread when the list never attached, so a later build that
  /// does render the list retries instead of leaving the position untouched.
  void _abandon() {
    _isApplyingThreadScroll = false;
    _trackedConversationId = null;
  }
}
