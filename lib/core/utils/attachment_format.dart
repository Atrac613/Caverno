/// Human-readable byte count for an attachment chip.
String formatAttachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Clip length as `M:SS`, or `S.Ss` under a minute.
String formatAttachmentDuration(int milliseconds) {
  if (milliseconds < 0) return '';
  final totalSeconds = milliseconds / 1000;
  if (totalSeconds < 60) return '${totalSeconds.toStringAsFixed(1)}s';
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).round();
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
