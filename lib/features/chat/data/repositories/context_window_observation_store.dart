import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/logger.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/context_window_observation.dart';

/// Null where no preferences are provided (widget and notifier tests), so a
/// frontend without storage simply learns nothing.
final contextWindowObservationStoreProvider =
    Provider<ContextWindowObservationStore?>((ref) {
      try {
        return ContextWindowObservationStore(
          ref.read(sharedPreferencesProvider),
        );
      } on ProviderException catch (error) {
        // Riverpod wraps the throwing preferences provider's error.
        if (error.exception is UnimplementedError) return null;
        rethrow;
      } on UnimplementedError {
        return null;
      }
    });

/// Persists [ContextWindowObservation]s per endpoint and model.
///
/// Writes only when an observation proves something new, so the many ordinary
/// requests that fit inside the known window cost no storage traffic.
final class ContextWindowObservationStore {
  ContextWindowObservationStore(this._preferences);

  static const preferencesKey = 'context_window_observations_v1';

  final SharedPreferences _preferences;
  Map<String, ContextWindowObservation>? _cache;

  Map<String, ContextWindowObservation> get _all => _cache ??= _load();

  ContextWindowObservation? read(String key) => _all[key];

  void accept(String key, int promptTokens, {bool pressured = false}) =>
      _update(
        key,
        (current) => current.accept(promptTokens, pressured: pressured),
        'accepted',
      );

  void reject(String key, {int? promptTokens, int? reportedLimit}) => _update(
    key,
    (current) => current.reject(
      promptTokens: promptTokens,
      reportedLimit: reportedLimit,
    ),
    'rejected',
  );

  void _update(
    String key,
    ContextWindowObservation? Function(ContextWindowObservation current) next,
    String event,
  ) {
    final updated = next(_all[key] ?? const ContextWindowObservation());
    if (updated == null) return;
    _all[key] = updated;
    appLog('[ContextWindow] $event $key ${jsonEncode(updated.toJson())}');
    _preferences.setString(
      preferencesKey,
      jsonEncode({
        for (final entry in _all.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  Map<String, ContextWindowObservation> _load() {
    try {
      final decoded = jsonDecode(
        _preferences.getString(preferencesKey) ?? '{}',
      );
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: ContextWindowObservation.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      };
    } on FormatException {
      return {};
    }
  }
}
