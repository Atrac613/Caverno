import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/personal_eval_case_repository.dart';
import '../../domain/entities/personal_eval_case.dart';

/// Local-only personal eval case store (LL19).
final personalEvalCaseRepositoryProvider = Provider<PersonalEvalCaseRepository>(
  (ref) => PersonalEvalCaseRepository(),
);

/// Exposes the recorded personal eval cases and their held-in / held-out
/// management to the UI.
final personalEvalCasesNotifierProvider =
    AsyncNotifierProvider<PersonalEvalCasesNotifier, List<PersonalEvalCase>>(
      PersonalEvalCasesNotifier.new,
    );

class PersonalEvalCasesNotifier extends AsyncNotifier<List<PersonalEvalCase>> {
  PersonalEvalCaseRepository get _repository =>
      ref.read(personalEvalCaseRepositoryProvider);

  @override
  Future<List<PersonalEvalCase>> build() => _repository.loadAll();

  List<PersonalEvalCase> _casesForSplit(
    List<PersonalEvalCase> cases,
    PersonalEvalCaseSplit split,
  ) {
    return cases.where((item) => item.split == split).toList(growable: false);
  }

  /// Cases on the given split from the current state (empty while loading).
  List<PersonalEvalCase> casesForSplit(PersonalEvalCaseSplit split) {
    return _casesForSplit(state.value ?? const [], split);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repository.loadAll);
  }

  Future<void> setSplit(String caseId, PersonalEvalCaseSplit split) async {
    await _repository.setSplit(caseId, split);
    await refresh();
  }

  Future<void> delete(String caseId) async {
    await _repository.delete(caseId);
    await refresh();
  }
}
