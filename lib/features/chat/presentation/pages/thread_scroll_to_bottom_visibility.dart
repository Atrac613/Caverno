import 'package:flutter/widgets.dart';

/// Whether the thread is scrolled away from its newest content, which is when
/// the scroll-to-latest button shows.
///
/// A [ValueNotifier], so listeners hear only real changes. It follows the
/// controller's own scroll events; callers also [update] after layout, since a
/// growing message moves `maxScrollExtent` without moving `pixels`.
class ThreadScrollToBottomVisibility extends ValueNotifier<bool> {
  ThreadScrollToBottomVisibility(this._controller, {required double epsilon})
    : _epsilon = epsilon,
      super(false) {
    _controller.addListener(update);
  }

  final ScrollController _controller;
  final double _epsilon;
  bool _isDisposed = false;

  void update() {
    if (_isDisposed) {
      return;
    }
    value =
        _controller.hasClients &&
        _controller.position.maxScrollExtent - _controller.position.pixels >
            _epsilon;
  }

  /// Dispose before the controller it listens to.
  @override
  void dispose() {
    _isDisposed = true;
    _controller.removeListener(update);
    super.dispose();
  }
}
