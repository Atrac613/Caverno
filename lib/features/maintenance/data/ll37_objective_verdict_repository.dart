import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/domain/entities/app_settings.dart';
import '../domain/entities/ll37_objective_verdict_record.dart';
import '../domain/services/ll37_verifier_fidelity_profile.dart';

class Ll37ObjectiveVerdictRepository {
  Ll37ObjectiveVerdictRepository(
    this._preferences, {
    this.fidelityRegistry = const Ll37VerifierFidelityRegistry(),
  });

  static const storageKey = 'll37_objective_verdict_history';
  static const maxRecords = 50;

  final SharedPreferences _preferences;
  final Ll37VerifierFidelityRegistry fidelityRegistry;

  List<Ll37ObjectiveVerdictRecord> loadAll() {
    final raw = _preferences.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <Ll37ObjectiveVerdictRecord>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <Ll37ObjectiveVerdictRecord>[];
      }
      final parsed = <Ll37ObjectiveVerdictRecord>[];
      for (final item in decoded) {
        try {
          if (item is! Map<String, dynamic>) continue;
          final record = Ll37ObjectiveVerdictRecord.fromJson(item);
          if (_matchesAcceptedRouteSlot(record)) parsed.add(record);
        } catch (_) {
          continue;
        }
      }
      parsed.sort(_newestFirst);
      final voteIds = <String>{};
      return List.unmodifiable(
        parsed.where((record) => voteIds.add(record.voteId)).take(maxRecords),
      );
    } catch (_) {
      return const <Ll37ObjectiveVerdictRecord>[];
    }
  }

  Future<List<Ll37ObjectiveVerdictRecord>> record(
    Ll37ObjectiveVerdictRecord record,
  ) async {
    final validated = Ll37ObjectiveVerdictRecord.fromJson(record.toJson());
    if (!_matchesAcceptedRouteSlot(validated)) {
      throw const FormatException(
        'verdict record does not match its accepted LL37 route slot',
      );
    }
    final updated = <Ll37ObjectiveVerdictRecord>[
      validated,
      ...loadAll().where((item) => item.voteId != validated.voteId),
    ]..sort(_newestFirst);
    final retained = List<Ll37ObjectiveVerdictRecord>.unmodifiable(
      updated.take(maxRecords),
    );
    final saved = await _preferences.setString(
      storageKey,
      jsonEncode(retained.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Failed to persist the LL37 objective verdict.');
    }
    return retained;
  }

  bool _matchesAcceptedRouteSlot(Ll37ObjectiveVerdictRecord record) {
    LlmProvider? provider;
    for (final item in LlmProvider.values) {
      if (item.name == record.verifierProvider) {
        provider = item;
        break;
      }
    }
    if (provider == null) return false;
    final profiles = fidelityRegistry.eligibleProfiles(
      provider: provider,
      baseUrl: record.verifierBaseUrl,
    );
    if (record.voteIndex < 1 || record.voteIndex > profiles.length) {
      return false;
    }
    final profile = profiles[record.voteIndex - 1];
    return record.verifierModel == profile.model &&
        record.verifierProfileKey == profile.profileKey &&
        record.fidelityReportSchemaVersion == profile.reportSchemaVersion &&
        record.fidelityReportSha256.toLowerCase() ==
            profile.reportSha256.toLowerCase();
  }

  static int _newestFirst(
    Ll37ObjectiveVerdictRecord left,
    Ll37ObjectiveVerdictRecord right,
  ) {
    final byTime = right.recordedAt.compareTo(left.recordedAt);
    if (byTime != 0) return byTime;
    final byCandidate = left.candidateId.compareTo(right.candidateId);
    return byCandidate != 0
        ? byCandidate
        : left.voteIndex.compareTo(right.voteIndex);
  }
}
