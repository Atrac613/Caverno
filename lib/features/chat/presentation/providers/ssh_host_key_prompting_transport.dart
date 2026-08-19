import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/ssh_host_key.dart';
import '../../../../core/services/ssh_host_key_providers.dart';
import '../../../../core/services/ssh_known_hosts_store.dart';
import '../../../../core/services/ssh_service.dart';
import '../../domain/entities/chat_turn_owner.dart';
import 'chat_ssh_tool_runtime.dart';
import 'ssh_host_key_prompt_controller.dart';
import 'ssh_service_chat_transport.dart';

/// Wraps [SshServiceChatTransport] so unknown and mismatched host keys prompt
/// the user before a second handshake, and never authenticate first.
final class SshHostKeyPromptingTransport implements ChatSshTransport {
  const SshHostKeyPromptingTransport({
    required ChatSshTransport inner,
    required SshKnownHostsStore store,
    required SshHostKeyPrompter prompts,
  }) : _inner = inner,
       _store = store,
       _prompts = prompts;

  final ChatSshTransport _inner;
  final SshKnownHostsStore _store;
  final SshHostKeyPrompter _prompts;

  @override
  ChatSshSession? activeSession(ChatTurnOwner owner) =>
      _inner.activeSession(owner);

  @override
  Future<void> connect(
    ChatTurnOwner owner,
    SshCredentialKey target,
    SshAuthCredential credential,
  ) async {
    try {
      await _inner.connect(owner, target, credential);
    } on SshUnknownHostKeyException catch (error) {
      await _confirmRememberAndRetry(
        owner,
        target,
        credential,
        error.decision,
      );
    } on SshHostKeyMismatchException catch (error) {
      await _confirmRememberAndRetry(
        owner,
        target,
        credential,
        error.decision,
      );
    }
  }

  Future<void> _confirmRememberAndRetry(
    ChatTurnOwner owner,
    SshCredentialKey target,
    SshAuthCredential credential,
    SshHostKeyDecision decision,
  ) async {
    final accepted = await _prompts.requestDecision(decision);
    if (!accepted) {
      throw SshHostKeyRejectedException(decision);
    }
    await _store.remember(decision.presented);
    await _inner.connect(owner, target, credential);
  }

  @override
  Future<String> execute(
    ChatTurnOwner owner,
    String command,
    String expectedFingerprint,
  ) => _inner.execute(owner, command, expectedFingerprint);

  @override
  Future<bool> disconnectIfFingerprint(
    ChatTurnOwner owner,
    String expectedFingerprint,
  ) => _inner.disconnectIfFingerprint(owner, expectedFingerprint);

  @override
  Future<void> clearOwner(ChatTurnOwner owner) => _inner.clearOwner(owner);
}

ChatSshTransport sshHostKeyAwareTransport(SshService service, Ref ref) {
  return SshHostKeyPromptingTransport(
    inner: SshServiceChatTransport(service),
    store: ref.read(sshKnownHostsStoreProvider),
    prompts: ref.read(sshHostKeyPromptControllerProvider.notifier),
  );
}
