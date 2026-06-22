import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/presentation/pages/personal_eval_record_page.dart';
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

class _CapturingNotifier extends PersonalEvalCasesNotifier {
  bool? capturedConsent;
  String? capturedPrompt;
  String? capturedRepoRef;
  PersonalEvalVerificationResult? capturedResult;
  var recordCount = 0;

  @override
  Future<List<PersonalEvalCase>> build() =>
      SynchronousFuture(const <PersonalEvalCase>[]);

  @override
  Future<PersonalEvalCase> recordFromSession({
    required LlmSessionLogContext context,
    required bool consentGranted,
    required String prompt,
    required String repoStateRef,
    String title = '',
    String? verificationCommand,
    PersonalEvalVerificationResult verificationResult =
        PersonalEvalVerificationResult.inconclusive,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
  }) async {
    recordCount += 1;
    capturedConsent = consentGranted;
    capturedPrompt = prompt;
    capturedRepoRef = repoStateRef;
    capturedResult = verificationResult;
    return PersonalEvalCase(
      caseId: 'x',
      prompt: prompt,
      repoStateRef: repoStateRef,
      consentGranted: consentGranted,
    );
  }
}

class _EmptyCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  const sessionContext = LlmSessionLogContext(
    workspaceMode: WorkspaceMode.coding,
    sessionId: 'session-7',
  );

  Future<_CapturingNotifier> pumpPage(WidgetTester tester) async {
    final notifier = _CapturingNotifier();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
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
                personalEvalCasesNotifierProvider.overrideWith(() => notifier),
                codingProjectsNotifierProvider.overrideWith(
                  _EmptyCodingProjectsNotifier.new,
                ),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const PersonalEvalRecordPage(
                  sessionContext: sessionContext,
                  initialPrompt: 'Fix the login crash',
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('Record stays disabled until consent and repo ref are set', (
    tester,
  ) async {
    await pumpPage(tester);

    FilledButton submit() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('personal-eval-record-submit')),
    );
    // Prompt is prefilled, but consent and repo ref are still missing.
    expect(submit().onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('personal-eval-record-consent')),
    );
    await tester.pump();
    expect(submit().onPressed, isNull); // repo ref still empty

    await tester.enterText(
      find.byKey(const ValueKey('personal-eval-record-repo-ref')),
      'abc123',
    );
    await tester.pump();
    expect(submit().onPressed, isNotNull);
  });

  testWidgets('records the session with the entered fields', (tester) async {
    final notifier = await pumpPage(tester);

    await tester.tap(
      find.byKey(const ValueKey('personal-eval-record-consent')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('personal-eval-record-repo-ref')),
      'abc123',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('personal-eval-record-submit')));
    await tester.pump();

    expect(notifier.recordCount, 1);
    expect(notifier.capturedConsent, isTrue);
    expect(notifier.capturedPrompt, 'Fix the login crash');
    expect(notifier.capturedRepoRef, 'abc123');
  });
}
