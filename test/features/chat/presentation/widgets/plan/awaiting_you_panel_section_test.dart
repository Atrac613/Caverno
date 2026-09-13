import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/plan_open_question_section.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

Conversation _conversation({
  List<String> openQuestions = const [],
  List<ConversationOpenQuestionProgress> progress = const [],
}) => Conversation(
  id: 'conversation-1',
  title: 'Plan thread',
  messages: const <Message>[],
  createdAt: DateTime(2026, 9, 14),
  updatedAt: DateTime(2026, 9, 14),
  workflowSpec: ConversationWorkflowSpec(openQuestions: openQuestions),
  openQuestionProgress: progress,
);

Future<void> _pump(
  WidgetTester tester,
  Conversation conversation, {
  List<int> opened = const [],
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
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Scaffold(
            body: AwaitingYouPanelSection(
              currentConversation: conversation,
              onOpen: () => opened.add(1),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('an untriaged question is waiting on the user', (tester) async {
    // The count that walked progress rows read zero here, because a row is
    // written only when someone presses a status button in the review sheet --
    // which is exactly the user this section exists for.
    await _pump(
      tester,
      _conversation(openQuestions: const ['Which API version is required?']),
    );

    expect(find.text('Waiting on you (1)'), findsOneWidget);
    expect(find.text('Which API version is required?'), findsOneWidget);
  });

  testWidgets('an answered question stops waiting', (tester) async {
    await _pump(
      tester,
      _conversation(
        openQuestions: const ['Which API version is required?'],
        progress: [
          ConversationOpenQuestionProgress(
            questionId: Conversation.openQuestionIdFor(
              'Which API version is required?',
            ),
            question: 'Which API version is required?',
            status: ConversationOpenQuestionStatus.resolved,
          ),
        ],
      ),
    );

    expect(find.byType(AwaitingYouPanelSection), findsOneWidget);
    expect(find.textContaining('Waiting on you'), findsNothing);
  });

  testWidgets('with nothing waiting it takes no height', (tester) async {
    await _pump(tester, _conversation());

    expect(tester.getSize(find.byType(AwaitingYouPanelSection)).height, 0);
  });

  testWidgets('it lists three and counts the rest', (tester) async {
    await _pump(
      tester,
      _conversation(
        openQuestions: const ['One?', 'Two?', 'Three?', 'Four?', 'Five?'],
      ),
    );

    expect(find.text('Waiting on you (5)'), findsOneWidget);
    expect(find.text('Three?'), findsOneWidget);
    expect(find.text('Four?'), findsNothing);
    expect(find.textContaining('2 more'), findsOneWidget);
  });

  testWidgets('tapping it opens the surface that answers', (tester) async {
    // A summary with one way in, not a second answering surface: the sheet
    // already owns the status menu and the note editor, and a decision with two
    // places to be made has two places to drift.
    final opened = <int>[];
    await _pump(
      tester,
      _conversation(openQuestions: const ['Which API version is required?']),
      opened: opened,
    );
    await tester.tap(find.text('Which API version is required?'));
    await tester.pump();

    expect(opened, hasLength(1));
  });
}
