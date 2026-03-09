class TemporalContextBuilder {
  TemporalContextBuilder._();

  static final RegExp _relativeDatePattern = RegExp(
    r'(今日|きょう|本日|昨日|明日|今週|先週|来週|最近|直近|latest|current|today|yesterday|tomorrow|this week|last week|next week|recent|now)',
    caseSensitive: false,
  );

  static String? build({required DateTime now, required String userInput}) {
    if (!_relativeDatePattern.hasMatch(userInput)) {
      return null;
    }

    final today = _dateOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final thisWeekStart = _startOfWeek(today);
    final thisWeekEnd = thisWeekStart.add(const Duration(days: 6));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = thisWeekEnd.subtract(const Duration(days: 7));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
    final nextWeekEnd = thisWeekEnd.add(const Duration(days: 7));
    final recentStart = today.subtract(const Duration(days: 30));

    final timeZoneName = now.timeZoneName.isEmpty ? 'Local' : now.timeZoneName;
    final offset = _formatUtcOffset(now.timeZoneOffset);

    return [
      '[Temporal Reference Context]',
      '- Source-of-truth local datetime: ${_formatDate(today)} ${_formatTime(now)} $timeZoneName (UTC$offset)',
      '- Resolve relative date expressions against this source-of-truth datetime.',
      '- today / 今日 = ${_formatDate(today)}',
      '- yesterday / 昨日 = ${_formatDate(yesterday)}',
      '- tomorrow / 明日 = ${_formatDate(tomorrow)}',
      '- this week / 今週 (Mon-Sun) = ${_formatDate(thisWeekStart)} to ${_formatDate(thisWeekEnd)}',
      '- last week / 先週 (Mon-Sun) = ${_formatDate(lastWeekStart)} to ${_formatDate(lastWeekEnd)}',
      '- next week / 来週 (Mon-Sun) = ${_formatDate(nextWeekStart)} to ${_formatDate(nextWeekEnd)}',
      '- recent / 最近 = ${_formatDate(recentStart)} to ${_formatDate(today)} (past 30 days)',
      '- If asked about latest/current/now, anchor to this datetime and include exact dates in the response.',
    ].join('\n');
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static DateTime _startOfWeek(DateTime value) {
    return value.subtract(Duration(days: value.weekday - DateTime.monday));
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }
}
