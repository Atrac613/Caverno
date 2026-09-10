/// How many finished background jobs a conversation keeps once the turn that
/// started them has retired, and the trim that enforces it.
///
/// A turn is not the lifetime of a background process, and it is not the
/// lifetime of the process's *result* either. Session 9174dbd1 lost the second
/// half: an iOS/macOS release job exited six seconds before its turn retired,
/// carrying only running jobs dropped it, and the next turn's
/// `process_list(include_finished: true)` answered `job_count: 0`. The release
/// had in fact succeeded; the user was told the outcome was unverifiable.
///
/// Keeping every finished job instead would pin each command's output buffers
/// for the life of the conversation, so the successor turn gets a recent
/// window and nothing more. The tools registry and the monitor service hold
/// different types over the same shape of pool, hence the callbacks.
abstract final class CarriedBackgroundJobRetention {
  static const int maxFinished = 8;

  /// Removes all but the [maxFinished] most recently started finished entries.
  ///
  /// Running entries are never removed: the pool is what keeps a live process
  /// reachable, and evicting one would report it gone while it still runs.
  static void trim<T>(
    Map<String, T> pool, {
    required bool Function(T entry) isRunning,
    required DateTime Function(T entry) startedAt,
    void Function(T entry)? onEvicted,
  }) {
    final finished =
        pool.entries.where((entry) => !isRunning(entry.value)).toList()
          ..sort((a, b) => startedAt(b.value).compareTo(startedAt(a.value)));
    for (final entry in finished.skip(maxFinished)) {
      pool.remove(entry.key);
      onEvicted?.call(entry.value);
    }
  }
}
