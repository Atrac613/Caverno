/// Builds the directive that tells the model a running turn was interrupted.
///
/// The interrupting text itself is an ordinary user turn in the transcript, so
/// this only has to say what that turn means: it is the current instruction,
/// not one more remark to file away behind the work already in flight.
final class TurnSteeringPromptBuilder {
  const TurnSteeringPromptBuilder._();

  /// Marker the session-log triage tooling can grep for.
  static const String marker = '[turn_steering]';

  static String directive({required int steerCount}) {
    final subject = steerCount == 1
        ? 'a new message'
        : '$steerCount new messages';
    return '$marker The user interrupted this turn with $subject while you '
        'were working. Those messages are the most recent user turns above, '
        'after the assistant output they interrupted. Treat them as the '
        'current instruction and act on them now, ahead of whatever you had '
        'planned next.\n'
        'Re-read them before your next step. If they change the goal, drop or '
        'redirect the work in progress to match; if they only add a '
        'constraint, keep going under that constraint; if they contradict a '
        'step you already completed, say so instead of pretending the earlier '
        'step matched.\n'
        'State in one sentence what you changed in response before you '
        'continue. Do not silently finish the original request as if the '
        'interruption had not arrived.';
  }
}
