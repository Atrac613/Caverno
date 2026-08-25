import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

/// Approves local commands as the turn asks for them.
///
/// SEC4.4g put a fresh, non-cacheable approval above both the approval cache
/// and Full Access for any command that reaches the native shell. A fixture
/// that used to run `dart analyze` or `printf` silently now waits for a
/// person, and a turn that never finishes cannot answer the question its test
/// is actually asking -- which tool ran, who owned the result, what the loop
/// did next. This stands in for that person.
///
/// A turn running on a thread the user is not reading routes its prompt to
/// that thread instead of the visible one, so the stand-in follows the same
/// path a person does: open the waiting thread, answer there, and go back to
/// where the user was. Without that it would only ever see the foreground
/// half, and every background turn would stall.
///
/// Deliberately not a way to opt out of the gate: the command still travels
/// the whole approval path and is still recorded in the audit log. Tests that
/// are *about* the dialog -- caching, denial, escalation -- must drive
/// [ChatNotifier.resolveLocalCommand] themselves rather than install this.
void standInForTheApprover(ProviderContainer container) {
  void answer(PendingLocalCommand pending) {
    container
        .read(chatNotifierProvider.notifier)
        .resolveLocalCommand(
          id: pending.id,
          approval: const LocalCommandApproval(approved: true),
        );
  }

  container.listen<ChatState>(chatNotifierProvider, (previous, next) {
    final pending = next.pendingLocalCommand;
    if (pending != null && pending.id != previous?.pendingLocalCommand?.id) {
      answer(pending);
      return;
    }
    // A turn on a thread the user is not reading routes its prompt to that
    // thread rather than the visible one, so `state` never shows it. The
    // person would meet it by opening that thread; the registry lets the
    // stand-in answer it without moving the user.
    for (final waiting
        in container
            .read(chatNotifierProvider.notifier)
            .pendingLocalCommandsAcrossThreads
            .toList(growable: false)) {
      answer(waiting);
    }
  });
}
