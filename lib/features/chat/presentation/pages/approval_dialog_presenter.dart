import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../widgets/approval/approval_dialog_route.dart';

/// Opens an approval or question dialog once per pending interaction, and
/// closes it again when that interaction is resolved somewhere else.
///
/// Both the desktop and the initiating Remote Coding device can answer the
/// same interaction, as can a connected Apple Watch for local interactions.
/// The pending state clearing dismisses the other surface.
///
/// Retains the exact route when presenting, so resolution can remove a covered
/// approval without disturbing any screen above it.
class ApprovalDialogPresenter {
  final Set<String> _openIds = <String>{};
  final Map<String, Route<dynamic>> _routes = {};

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
      _dismiss(previousId);
    }
    if (next == null || nextId == previousId) return;
    if (shouldPresent != null && !shouldPresent(next)) return;
    _presentOnce(context, nextId!, isMounted, () => present(next));
  }

  void _presentOnce(
    BuildContext context,
    String id,
    bool Function() isMounted,
    Future<void> Function() present,
  ) {
    if (!_openIds.add(id)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      if (!isMounted() || !context.mounted || !_openIds.contains(id)) {
        _openIds.remove(id);
        return;
      }
      try {
        // Presenters push their named route synchronously before awaiting its
        // result. A predicate that always returns true inspects the top route
        // without popping it or any unrelated route.
        final navigator = Navigator.of(context);
        final completion = present();
        navigator.popUntil((route) {
          if (route.settings.name == approvalDialogRouteName(id)) {
            _routes[id] = route;
          }
          return true;
        });
        await completion;
      } finally {
        _routes.remove(id);
        _openIds.remove(id);
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _dismiss(String id) {
    if (!_openIds.remove(id)) return;
    final route = _routes.remove(id);
    if (route == null) return;
    // State may clear during a build or a navigation callback. Defer mutation
    // until the frame finishes, then check for a concurrent local dismissal.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}
