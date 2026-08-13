import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/services/retry_until_green_coordinator.dart';

final retryUntilGreenReportRepositoryProvider =
    Provider<RetryUntilGreenReportRepository>((ref) {
      return RetryUntilGreenReportRepository(
        ref.watch(sharedPreferencesProvider),
      );
    });

/// Persists bounded retry reports; loading never starts or resumes a run.
class RetryUntilGreenReportRepository {
  RetryUntilGreenReportRepository(this._prefs);

  static const storageKey = 'retry_until_green_reports';
  static const maxStoredReports = 32;

  final SharedPreferences _prefs;

  List<RetryUntilGreenReport> loadAll() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => RetryUntilGreenReport.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(Iterable<RetryUntilGreenReport> reports) {
    final bounded = reports.take(maxStoredReports).toList(growable: false);
    return _prefs.setString(
      storageKey,
      jsonEncode([for (final report in bounded) report.toJson()]),
    );
  }
}
