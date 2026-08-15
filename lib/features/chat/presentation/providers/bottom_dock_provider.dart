import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the bottom dock is showing.
enum BottomDockTab { terminal, runLog, issues }

/// Which tab each thread's bottom dock is on.
///
/// Separate from the terminal service, which owns the shell session and the
/// open/closed flag: the dock is now shared by three panes and the terminal is
/// only one of them. Per thread, because two coding threads run different apps
/// and should not steal each other's view.
class BottomDockTabNotifier extends Notifier<Map<String, BottomDockTab>> {
  @override
  Map<String, BottomDockTab> build() => const {};

  BottomDockTab tabFor(String? threadId) =>
      state[threadId ?? ''] ?? BottomDockTab.terminal;

  void select(String? threadId, BottomDockTab tab) {
    state = {...state, threadId ?? '': tab};
  }
}

final bottomDockTabProvider =
    NotifierProvider<BottomDockTabNotifier, Map<String, BottomDockTab>>(
      BottomDockTabNotifier.new,
    );
