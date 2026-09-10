/// Compact elapsed time for live status rows: `8s`, `14m 8s`, `2h 14m`.
///
/// Mirrors the watch transcript's formatter (CavernoWatch `TranscriptView`) so a
/// turn reads the same on both surfaces. Seconds are not zero-padded.
///
/// The hour tier is load-bearing rather than cosmetic: without it a stale or
/// synthetic timestamp renders as `149760m 12s`.
String formatCompactDuration(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
