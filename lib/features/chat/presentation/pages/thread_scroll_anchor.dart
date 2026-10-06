import 'package:flutter/foundation.dart';

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
