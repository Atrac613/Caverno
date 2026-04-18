import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/plan_review_sheet.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

Future<void> _pumpPlanReviewSheet(
  WidgetTester tester, {
  required ConversationPlanArtifact artifact,
  required bool isPlanMode,
  required bool canApprove,
  required bool canCancel,
}) async {
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
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: PlanReviewSheet(
                planArtifact: artifact,
                isPlanMode: isPlanMode,
                canApprove: canApprove,
                canCancel: canCancel,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('shows full plan review with approve action for drafts', (
    tester,
  ) async {
    await _pumpPlanReviewSheet(
      tester,
      artifact: const ConversationPlanArtifact(
        draftMarkdown: '# Draft plan\n\n## Tasks\n\n- Implement ping utility',
      ),
      isPlanMode: true,
      canApprove: true,
      canCancel: true,
    );

    expect(find.text('Suggested plan'), findsOneWidget);
    expect(find.text('Approve and start'), findsOneWidget);
    expect(find.text('Implement ping utility'), findsOneWidget);
  });
}
