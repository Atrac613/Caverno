import 'dart:convert';

final class FirebaseCliEnvelope {
  const FirebaseCliEnvelope({
    required this.success,
    required this.result,
    required this.error,
  });

  final bool success;
  final Object? result;
  final String? error;

  factory FirebaseCliEnvelope.parse(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Firebase CLI output must be an object.');
    }
    final status = decoded['status'];
    if (status == 'success') {
      return FirebaseCliEnvelope(
        success: true,
        result: decoded['result'],
        error: null,
      );
    }
    final error = decoded['error'];
    if (status == 'error' && error is String && error.isNotEmpty) {
      return FirebaseCliEnvelope(success: false, result: null, error: error);
    }
    throw const FormatException('Firebase CLI status is invalid.');
  }
}

bool hasDefaultFirestoreDatabase(FirebaseCliEnvelope envelope) {
  final result = envelope.result;
  return envelope.success &&
      result is List<Object?> &&
      result.whereType<Map<String, Object?>>().any(
        (database) =>
            database['name'] is String &&
            (database['name'] as String).endsWith('/databases/(default)') &&
            database['type'] == 'FIRESTORE_NATIVE',
      );
}

String? defaultFirestoreLocation(FirebaseCliEnvelope envelope) {
  final result = envelope.result;
  if (!envelope.success || result is! List<Object?>) {
    return null;
  }
  for (final database in result.whereType<Map<String, Object?>>()) {
    final name = database['name'];
    final location = database['locationId'];
    if (name is String &&
        name.endsWith('/databases/(default)') &&
        location is String) {
      return location;
    }
  }
  return null;
}

String? defaultHostingUrl(FirebaseCliEnvelope envelope) {
  final result = envelope.result;
  if (!envelope.success || result is! Map<String, Object?>) {
    return null;
  }
  final sites = result['sites'];
  if (sites is! List<Object?>) {
    return null;
  }
  for (final site in sites.whereType<Map<String, Object?>>()) {
    final url = site['defaultUrl'];
    if (site['type'] == 'DEFAULT_SITE' && url is String) {
      return url;
    }
  }
  return null;
}

bool hasActiveNotificationRelay(FirebaseCliEnvelope envelope) {
  final result = envelope.result;
  if (!envelope.success || result is! List<Object?>) {
    return false;
  }
  final activeIds = result
      .whereType<Map<String, Object?>>()
      .where(
        (function) =>
            function['codebase'] == 'notification-relay' &&
            function['region'] == 'asia-northeast1' &&
            function['runtime'] == 'nodejs22' &&
            function['state'] == 'ACTIVE',
      )
      .map((function) => function['id'])
      .whereType<String>()
      .toSet();
  return activeIds.contains('notificationRelay') &&
      activeIds.contains('retryNotificationDeliveries');
}
