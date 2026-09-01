import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../widgets/approval/approval_dialog_route.dart';

/// Opens an approval or question dialog once per pending interaction, and
/// closes it again when that interaction is resolved somewhere else.
///
/// "Somewhere else" is the Apple Watch today. The phone used to only open these
/// dialogs: closing was the job of whoever answered, and the phone was always
/// the answerer. Remote Coding never broke that assumption because
/// `shouldPresentDesktopQuestion` suppresses remote-origin interactions
/// outright. The watch is deliberately local-origin — it is a peripheral of
/// this device, not a paired principal — so the phone does present the sheet,
/// and something has to take it away when the wrist answers first.
///
/// Dismissal pops by route name rather than popping whatever is on top.
/// `popUntil` with a name predicate is the safe primitive here: it pops the
/// dialog when it is topmost and does nothing at all when something else is,
/// so a mistimed resolution can never dismiss an unrelated screen.
class ApprovalDialogPresenter {
  final Set<String> _openIds = <String>{};

  bool isOpen(String id) => _openIds.contains(id);

  /// Reacts to one pending interaction changing.
  ///
  /// Opening is deferred to the next frame so it cannot fire during a build or
  /// an `InheritedElement` lifecycle transition, which used to trip
  /// `_dependents.isEmpty` assertions.
  void sync<T extends Object>({
    required BuildContext context,
    required T? previous,
    required T? next,
    required String Function(T) idOf,
    required Future<void> Function(T) present,
    required bool Function() isMounted,
    bool Function(T)? shouldPresent,
  }) {
    final previousId = previous == null ? null : idOf(previous);
    final nextId = next == null ? null : idOf(next);
    if (previousId != null && previousId != nextId) {
      _dismiss(context, previousId);
    }
    if (next == null || nextId == previousId) return;
    if (shouldPresent != null && !shouldPresent(next)) return;
    _presentOnce(nextId!, isMounted, () => present(next));
  }

  void _presentOnce(
    String id,
    bool Function() isMounted,
    Future<void> Function() present,
  ) {
    if (!_openIds.add(id)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!isMounted()) {
        _openIds.remove(id);
        return;
      }
      try {
        await present();
      } finally {
        _openIds.remove(id);
      }
    });
  }

  void _dismiss(BuildContext context, String id) {
    if (!_openIds.remove(id)) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return;
    final name = approvalDialogRouteName(id);
    navigator.popUntil((route) => route.settings.name != name);
  }
}
