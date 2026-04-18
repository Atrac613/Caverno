import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/timeline_plan_card.dart';

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

Future<void> _pumpTimelinePlanCard(
  WidgetTester tester, {
  required Conversation conversation,
  required bool isApprovedExpanded,
  ChatState? chatState,
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
              body: TimelinePlanCard(
                currentConversation: conversation,
                chatState: chatState ?? ChatState.initial(),
                isPlanMode: isPlanMode,
                isApprovedExpanded: isApprovedExpanded,
                onToggleApprovedExpanded: () {},
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

  testWidgets('keeps approved plan markdown collapsed until expanded', (
    tester,
  ) async {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const [],
      createdAt: DateTime(2026, 4, 18, 12),
      updatedAt: DateTime(2026, 4, 18, 12),
      workspaceMode: WorkspaceMode.coding,
      planArtifact: const ConversationPlanArtifact(
        approvedMarkdown: '# Approved plan\n\n- Ship the refactor',
      ),
    );

    await _pumpTimelinePlanCard(
      tester,
      conversation: conversation,
      isApprovedExpanded: false,
    );

    expect(find.text('Expand details'), findsOneWidget);

    await _pumpTimelinePlanCard(
      tester,
      conversation: conversation,
      isApprovedExpanded: true,
    );

    expect(find.text('Collapse details'), findsOneWidget);
    expect(find.text('Approved plan'), findsOneWidget);
    expect(find.text('Ship the refactor'), findsOneWidget);
  });

  testWidgets(
    'shows progress state instead of a disabled approve button while plan generation is still running',
    (tester) async {
      final conversation = Conversation(
        id: 'conversation-2',
        title: 'Draft plan thread',
        messages: const [],
        createdAt: DateTime(2026, 4, 18, 12),
        updatedAt: DateTime(2026, 4, 18, 12),
        workspaceMode: WorkspaceMode.coding,
        planArtifact: const ConversationPlanArtifact(
          draftMarkdown: '# Draft plan\n\n## Goal\n\nCreate the CLI utility',
        ),
      );

      await _pumpTimelinePlanCard(
        tester,
        conversation: conversation,
        isApprovedExpanded: false,
        isPlanMode: true,
        chatState: const ChatState(
          messages: [],
          isLoading: true,
          isGeneratingTaskProposal: true,
        ),
      );

      expect(
        find.text('Generating a workflow and task breakdown...'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Approve & Start'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );
}
