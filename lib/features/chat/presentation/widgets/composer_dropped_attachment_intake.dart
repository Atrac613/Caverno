import 'package:flutter/widgets.dart';

/// Tracks which dropped attachment the composer has already taken.
///
/// The "handled" callback clears the pending drop on the page, and the
/// composer calls [take] from `initState` and `didUpdateWidget` — the page is
/// mid-build at that moment, so a synchronous call would mark an ancestor
/// dirty during its own build and trip the framework's `!_dirty` assertion on
/// every drop. Deferring to the end of the frame is the whole point of this
/// class; the page guards its own `mounted` before it acts.
class DroppedAttachmentIntake {
  int? _handledId;

  /// Claims the attachment with [id], or returns false if it is already taken.
  bool take(int id, VoidCallback? onHandled) {
    if (id == _handledId) return false;
    _handledId = id;
    if (onHandled != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onHandled());
    }
    return true;
  }

  /// Whether [id] is still the attachment this intake is working on.
  bool isCurrent(int id) => id == _handledId;
}
