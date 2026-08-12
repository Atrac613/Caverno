import 'dart:io';

import '../src/retry_policy.dart';
import '../src/task_state.dart';

/// Verifier for the `taskflow` fixture. Exit 0 means every check passed.
void main(List<String> args) {
  final failures = <String>[];
  const machine = TaskStateMachine();

  void check(String name, Object? actual, Object? expected) {
    final a = _describe(actual);
    final e = _describe(expected);
    if (a != e) {
      failures.add('$name\n  expected: $e\n  actual:   $a');
    }
  }

  // terminal_states
  check('done is terminal', machine.isTerminal(TaskState.done), true);
  check('failed is terminal', machine.isTerminal(TaskState.failed), true);
  check('cancelled is terminal', machine.isTerminal(TaskState.cancelled), true);
  check(
    'running is not terminal',
    machine.isTerminal(TaskState.running),
    false,
  );
  check('queued is not terminal', machine.isTerminal(TaskState.queued), false);

  // legal_transitions
  check(
    'queued can start running',
    machine.canTransition(TaskState.queued, TaskState.running),
    true,
  );
  check(
    'running can pause',
    machine.canTransition(TaskState.running, TaskState.paused),
    true,
  );
  check(
    'paused can resume',
    machine.canTransition(TaskState.paused, TaskState.running),
    true,
  );
  check(
    'queued cannot finish directly',
    machine.canTransition(TaskState.queued, TaskState.done),
    false,
  );
  check(
    'paused cannot finish directly',
    machine.canTransition(TaskState.paused, TaskState.done),
    false,
  );

  // terminal_is_final
  check(
    'a done task cannot run again',
    machine.canTransition(TaskState.done, TaskState.running),
    false,
  );
  check(
    'a cancelled task cannot run again',
    machine.canTransition(TaskState.cancelled, TaskState.running),
    false,
  );
  check(
    'a late event cannot resurrect a done task',
    machine.transition(TaskState.done, TaskState.running),
    TaskState.done,
  );

  // self_transition
  check(
    'a state cannot transition to itself',
    machine.canTransition(TaskState.running, TaskState.running),
    false,
  );

  // replay
  check(
    'replay follows a legal sequence',
    machine.replay(TaskState.queued, [
      TaskState.running,
      TaskState.paused,
      TaskState.running,
      TaskState.done,
    ]),
    TaskState.done,
  );
  check(
    'replay ignores an illegal step',
    machine.replay(TaskState.queued, [TaskState.done, TaskState.running]),
    TaskState.running,
  );
  check(
    'replay stops at a terminal state',
    machine.replay(TaskState.queued, [
      TaskState.running,
      TaskState.cancelled,
      TaskState.running,
    ]),
    TaskState.cancelled,
  );

  // backoff
  const policy = RetryPolicy();
  check('no delay before the first try', policy.delayFor(0), Duration.zero);
  check(
    'first retry uses the base delay',
    policy.delayFor(1),
    const Duration(milliseconds: 100),
  );
  check(
    'the delay doubles',
    policy.delayFor(3),
    const Duration(milliseconds: 400),
  );
  check(
    'the delay is capped',
    policy.delayFor(20),
    const Duration(seconds: 30),
  );
  check(
    'a huge attempt stays capped and positive',
    policy.delayFor(4000),
    const Duration(seconds: 30),
  );

  // retry_budget
  check(
    'retries stop at the attempt limit',
    policy.shouldRetry(attempt: 5, cancelled: false),
    false,
  );
  check(
    'retries continue below the limit',
    policy.shouldRetry(attempt: 4, cancelled: false),
    true,
  );
  check(
    'cancellation stops retrying immediately',
    policy.shouldRetry(attempt: 1, cancelled: true),
    false,
  );
  check(
    'total backoff sums every permitted retry',
    policy.totalBackoff(),
    const Duration(milliseconds: 1500),
  );

  if (failures.isEmpty) {
    stdout.writeln('taskflow verify: all checks passed');
    exit(0);
  }
  stderr.writeln('taskflow verify: ${failures.length} check(s) failed\n');
  for (final failure in failures) {
    stderr.writeln(failure);
    stderr.writeln('');
  }
  exit(1);
}

String _describe(Object? value) {
  if (value is Duration) {
    return '${value.inMicroseconds}us';
  }
  return value is String ? '"$value"' : '$value';
}
