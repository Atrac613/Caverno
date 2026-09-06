/// Whether an `error` payload from the desktop ends the session.
///
/// Almost none of them do. An `error` arrives on a socket that is still open,
/// and a session that has actually ended arrives as a close instead. The client
/// used to treat every one as a disconnection, which cost two things at once:
///
/// - `RemoteCodingPage` renders the pairing view whenever `isConnected` is
///   false, so a single declined command replaced the whole UI — the thread
///   list and the button that creates a thread included — with a screen asking
///   the user to pair again.
/// - The reset cleared `pendingApproval`, so a rejection of some unrelated
///   command took a still-pending approval off the phone while the desktop went
///   on waiting for an answer to it.
///
/// So the default is that a code is a declined command. A new code from a newer
/// desktop is therefore shown rather than acted on, which is the recoverable
/// reading; a code that really is fatal is named here.
abstract final class RemoteCodingErrorPolicy {
  /// Voids the saved credential, so the client also forgets the host. Handled
  /// separately from [endsTheSession] because it does more than end a session.
  static const String unauthorized = 'unauthorized';

  /// Answered before a session exists. The connection view is where the user
  /// retries from, so it is the right screen to land on.
  static const String pairingFailed = 'pairing_failed';

  static bool endsTheSession(String code) => code.trim() == pairingFailed;

  /// Whether [code] should leave the connection alone and only be reported.
  static bool isDeclinedCommand(String code) {
    final trimmed = code.trim();
    return trimmed != unauthorized && !endsTheSession(trimmed);
  }
}
