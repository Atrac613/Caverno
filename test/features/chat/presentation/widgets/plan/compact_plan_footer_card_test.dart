import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/compact_plan_footer_card.dart';

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

Future<void> _pumpCompactPlanFooterCard(
  WidgetTester tester, {
  required Conversation conversation,
  bool isPlanMode = false,
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
              body: CompactPlanFooterCard(
                currentConversation: conversation,
                isPlanMode: isPlanMode,
                onOpen: () {},
                onApprove: () {},
                onEdit: () {},
                onCancel: () {},
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

  testWidgets('shows compact draft actions without markdown body', (
    tester,
  ) async {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Draft thread',
      messages: const [],
      createdAt: DateTime(2026, 4, 18, 12),
      updatedAt: DateTime(2026, 4, 18, 12),
      workspaceMode: WorkspaceMode.coding,
      planArtifact: const ConversationPlanArtifact(
        draftMarkdown: '# Draft plan\n\n- Implement ping utility',
      ),
    );

    await _pumpCompactPlanFooterCard(tester, conversation: conversation);

    expect(find.text('Suggested plan'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Expand details'), findsOneWidget);
    expect(find.text('Approve and start'), findsOneWidget);
    expect(find.text('Implement ping utility'), findsNothing);
  });
}
