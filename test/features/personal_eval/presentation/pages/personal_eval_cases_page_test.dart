import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/personal_eval/domain/entities/personal_eval_bake_off_report.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_replay_run.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_session_log_summary.dart';
import 'package:caverno/features/personal_eval/presentation/pages/personal_eval_cases_page.dart';
import 'package:caverno/features/personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

/// Fake notifier with synchronous in-memory data so the page test never spins
/// on the async loading state (real file IO + a progress indicator would make
/// pumpAndSettle time out). The repository is covered by its own tests.
class _FakeCasesNotifier extends PersonalEvalCasesNotifier {
  _FakeCasesNotifier(this._cases, {this.replayResult, this.bakeOffResult});

  List<PersonalEvalCase> _cases;
  final PersonalEvalReplayRun? replayResult;
  final PersonalEvalBakeOffReport? bakeOffResult;
  final List<String> replayedCaseIds = [];
  final List<String> bakeOffCandidates = [];

  @override
  Future<List<PersonalEvalCase>> build() => SynchronousFuture(_cases);

  @override
  Future<PersonalEvalReplayRun> replayCase(String caseId) async {
    replayedCaseIds.add(caseId);
    return replayResult ??
        PersonalEvalReplayRun(label: 'replay', cases: const []);
  }

  @override
  Future<PersonalEvalBakeOffReport> runBakeOff({
    required String candidateModel,
  }) async {
    bakeOffCandidates.add(candidateModel);
    return bakeOffResult ??
        const PersonalEvalBakeOffReport(label: 'bake-off', entries: []);
  }

  @override
  Future<void> setSplit(String caseId, PersonalEvalCaseSplit split) async {
    _cases = _cases
        .map(
          (item) => item.caseId == caseId ? item.copyWith(split: split) : item,
        )
        .toList(growable: false);
    state = AsyncData(_cases);
  }

  @override
  Future<void> delete(String caseId) async {
    _cases = _cases
        .where((item) => item.caseId != caseId)
        .toList(growable: false);
    state = AsyncData(_cases);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  PersonalEvalCase caseWith(
    String id, {
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    String title = '',
  }) {
    return PersonalEvalCase(
      caseId: id,
      title: title,
      prompt: 'Fix the bug in $id',
      repoStateRef: 'abc',
      consentGranted: true,
      split: split,
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    List<PersonalEvalCase> cases, {
    _FakeCasesNotifier? notifier,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        saveLocale: false,
        assetLoader: const _TestTranslationLoader(),
        child: Builder(
          builder: (context) {
            return ProviderScope(
              overrides: [
                personalEvalCasesNotifierProvider.overrideWith(
                  () => notifier ?? _FakeCasesNotifier(cases),
                ),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const PersonalEvalCasesPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state when no cases are stored', (tester) async {
    await pumpPage(tester, const []);

    expect(
      find.text(
        'No recorded cases yet. '
        'Record a completed session to build your eval suite.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('lists cases and moves one across the split', (tester) async {
    await pumpPage(tester, [caseWith('a', title: 'Login crash')]);

    expect(find.text('Login crash'), findsOneWidget);
    expect(find.text('Held-in (1)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('personal-eval-case-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to held-out'));
    await tester.pumpAndSettle();

    expect(find.text('Held-out (1)'), findsOneWidget);
    expect(find.text('Held-in (1)'), findsNothing);
  });

  testWidgets('deletes a case from the overflow menu', (tester) async {
    await pumpPage(tester, [caseWith('a', title: 'Login crash')]);

    await tester.tap(find.byKey(const ValueKey('personal-eval-case-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Login crash'), findsNothing);
  });

  testWidgets('runs a replay from the overflow menu and shows the verdict', (
    tester,
  ) async {
    final notifier = _FakeCasesNotifier(
      [caseWith('a', title: 'Login crash')],
      replayResult: const PersonalEvalReplayRun(
        label: 'replay',
        cases: [
          PersonalEvalReplayCaseResult(
            caseId: 'a',
            verificationResult: PersonalEvalVerificationResult.passed,
            summary: PersonalEvalSessionLogSummary(totalDurationMs: 90),
          ),
        ],
      ),
    );
    await pumpPage(tester, const [], notifier: notifier);

    await tester.tap(find.byKey(const ValueKey('personal-eval-case-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run replay'));
    await tester.pump();

    expect(notifier.replayedCaseIds, ['a']);
    expect(find.text('Replay finished: Passed (90 ms)'), findsOneWidget);
  });

  testWidgets('runs a bake-off and shows the recommendation', (tester) async {
    final notifier = _FakeCasesNotifier(
      [caseWith('a', title: 'Login crash')],
      bakeOffResult: const PersonalEvalBakeOffReport(
        label: 'bake-off',
        incumbentModel: 'old',
        candidateModel: 'new',
        entries: [
          PersonalEvalBakeOffCaseEntry(
            caseId: 'a',
            title: 'Login crash',
            split: PersonalEvalCaseSplit.heldIn,
            status: PersonalEvalBakeOffStatus.improved,
            expectedToolCallCount: 0,
            improvements: ['verification result improved failed->passed'],
          ),
        ],
      ),
    );
    await pumpPage(tester, const [], notifier: notifier);

    await tester.tap(find.byKey(const ValueKey('personal-eval-bake-off')));
    await tester.pumpAndSettle();

    // Candidate model prompt.
    await tester.enterText(find.byType(TextField), 'new-model');
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(notifier.bakeOffCandidates, ['new-model']);
    // The verdict dialog shows the recommendation.
    expect(
      find.byKey(const ValueKey('personal-eval-bake-off-report')),
      findsOneWidget,
    );
    expect(find.text('Adopt candidate'), findsOneWidget);
  });
}
