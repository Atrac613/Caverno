import '../../../../core/services/ssh_service.dart';
import '../../domain/entities/chat_turn_owner.dart';
import 'chat_ssh_tool_runtime.dart';

/// Binds [ChatSshToolRuntime] to the real [SshService].
///
/// The runtime is deliberately transport-agnostic so its ownership rules can be
/// tested without a network: every method here is a direct forward, and the
/// owner is passed through rather than resolved from anything ambient. A
/// transport that looked up "the current session" instead of the owner's would
/// let one thread's `ssh_execute_command` run against another thread's host.
final class SshServiceChatTransport implements ChatSshTransport {
  const SshServiceChatTransport(this._service);

  final SshService _service;

  @override
  ChatSshSession? activeSession(ChatTurnOwner owner) {
    final session = _service.activeSession(owner: owner);
    if (session == null) return null;
    return (
      host: session.host,
      port: session.port,
      username: session.username,
      fingerprint: session.fingerprint,
    );
  }

  @override
  Future<void> connect(
    ChatTurnOwner owner,
    SshCredentialKey target,
    SshAuthCredential credential,
  ) => _service.connect(
    owner: owner,
    host: target.host,
    port: target.port,
    username: target.username,
    credential: credential,
  );

  /// Runs [command] only while the session still carries
  /// [expectedFingerprint], so a session replaced mid-operation fails instead
  /// of running the command against the new host.
  @override
  Future<String> execute(
    ChatTurnOwner owner,
    String command,
    String expectedFingerprint,
  ) async {
    final result = await _service.execute(
      owner: owner,
      command: command,
      expectedFingerprint: expectedFingerprint,
    );
    return result.formatted();
  }

  @override
  Future<bool> disconnectIfFingerprint(
    ChatTurnOwner owner,
    String expectedFingerprint,
  ) => _service.disconnectIfFingerprint(
    owner: owner,
    expectedFingerprint: expectedFingerprint,
  );

  @override
  Future<void> clearOwner(ChatTurnOwner owner) =>
      _service.clearOwner(owner: owner);
}
