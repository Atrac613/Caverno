import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/ll37_objective_verdict_repository.dart';
import '../../domain/entities/ll37_objective_verdict_record.dart';

final ll37ObjectiveVerdictRepositoryProvider =
    Provider<Ll37ObjectiveVerdictRepository>((ref) {
      return Ll37ObjectiveVerdictRepository(
        ref.watch(sharedPreferencesProvider),
      );
    });

final ll37ObjectiveVerdictHistoryNotifierProvider =
    NotifierProvider<
      Ll37ObjectiveVerdictHistoryNotifier,
      List<Ll37ObjectiveVerdictRecord>
    >(Ll37ObjectiveVerdictHistoryNotifier.new);

class Ll37ObjectiveVerdictHistoryNotifier
    extends Notifier<List<Ll37ObjectiveVerdictRecord>> {
  late Ll37ObjectiveVerdictRepository _repository;

  @override
  List<Ll37ObjectiveVerdictRecord> build() {
    _repository = ref.watch(ll37ObjectiveVerdictRepositoryProvider);
    return _repository.loadAll();
  }

  List<Ll37ObjectiveVerdictRecord> recordsForCandidate(String candidateId) {
    final normalized = candidateId.trim();
    if (normalized.isEmpty) return const [];
    return List.unmodifiable(
      state.where((record) => record.candidateId == normalized),
    );
  }

  Future<void> record(Ll37ObjectiveVerdictRecord record) async {
    state = await _repository.record(record);
  }
}
