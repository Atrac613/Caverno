import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

final class RemoteCodingNotificationReceiptStore {
  RemoteCodingNotificationReceiptStore(
    this._preferences, {
    this.maximumReceipts = 128,
    this.retention = const Duration(days: 7),
  });

  static const String _storageKey =
      'remote_coding_terminal_notification_receipts';

  final SharedPreferences _preferences;
  final int maximumReceipts;
  final Duration retention;
  Future<void> _pendingMutation = Future<void>.value();

  Future<bool> claim(String eventId, DateTime receivedAt) {
    final result = _pendingMutation.then(
      (_) => _claim(eventId.trim(), receivedAt.toUtc()),
    );
    _pendingMutation = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> _claim(String eventId, DateTime receivedAt) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(eventId)) {
      throw const FormatException('Notification event ID is invalid.');
    }
    final cutoff = receivedAt.subtract(retention);
    final receipts = _load()
      ..removeWhere((_, timestamp) => !timestamp.isAfter(cutoff));
    if (receipts.containsKey(eventId)) {
      return false;
    }
    receipts[eventId] = receivedAt;
    final ordered = receipts.entries.toList(growable: false)
      ..sort((left, right) => right.value.compareTo(left.value));
    final bounded = ordered.take(maximumReceipts);
    final saved = await _preferences.setString(
      _storageKey,
      jsonEncode(<String, String>{
        for (final entry in bounded) entry.key: entry.value.toIso8601String(),
      }),
    );
    if (!saved) {
      throw StateError('Notification receipt cache could not be saved.');
    }
    return true;
  }

  Map<String, DateTime> _load() {
    try {
      final raw = _preferences.getString(_storageKey);
      final decoded = jsonDecode(raw ?? '{}');
      if (decoded is! Map) {
        return <String, DateTime>{};
      }
      return <String, DateTime>{
        for (final entry in decoded.entries)
          if (DateTime.tryParse(entry.value.toString()) case final parsed?)
            entry.key.toString(): parsed.toUtc(),
      };
    } catch (_) {
      return <String, DateTime>{};
    }
  }
}
