import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/ssh_host_key.dart';

abstract interface class SshHostKeyPrompter {
  Future<bool> requestDecision(SshHostKeyDecision decision);
}

final class SshHostKeyPrompt {
  SshHostKeyPrompt({
    required this.id,
    required this.decision,
    required this.completer,
  });

  final int id;
  final SshHostKeyDecision decision;
  final Completer<bool> completer;
}

final class SshHostKeyPromptController extends Notifier<SshHostKeyPrompt?>
    implements SshHostKeyPrompter {
  int _nextId = 0;

  @override
  SshHostKeyPrompt? build() => null;

  @override
  Future<bool> requestDecision(SshHostKeyDecision decision) async {
    final completer = Completer<bool>();
    final prompt = SshHostKeyPrompt(
      id: ++_nextId,
      decision: decision,
      completer: completer,
    );
    state = prompt;
    try {
      return await completer.future;
    } finally {
      if (identical(state, prompt)) {
        state = null;
      }
    }
  }

  void resolve(bool accepted) {
    final pending = state;
    if (pending == null || pending.completer.isCompleted) return;
    pending.completer.complete(accepted);
  }
}

final sshHostKeyPromptControllerProvider =
    NotifierProvider<SshHostKeyPromptController, SshHostKeyPrompt?>(
      SshHostKeyPromptController.new,
    );
