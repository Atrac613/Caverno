import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/awaiting_you_sheet.dart';
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

const _claim = 'The staging database is a copy of production';
const _question = 'Which API version is required?';
const _provenanceService = ConversationContractProvenanceService();

ConversationContractItemProvenance _mark({
  bool assumption = true,
  bool material = true,
  bool confirmed = false,
}) => ConversationContractItemProvenance(
  itemId: _provenanceService.itemId(
    kind: ConversationContractItemKind.constraint,
    value: _claim,
  ),
  kind: ConversationContractItemKind.constraint,
  assumption: assumption,
  material: material,
  confirmed: confirmed,
);

Conversation _conversation({
  List<String> openQuestions = const [],
  List<String> constraints = const [],
  List<ConversationContractItemProvenance> provenance = const [],
}) => Conversation(
  id: 'conversation-1',
  title: 'Plan thread',
  messages: const <Message>[],
  createdAt: DateTime(2026, 9, 20),
  updatedAt: DateTime(2026, 9, 20),
  workflowSpec: ConversationWorkflowSpec(
    openQuestions: openQuestions,
    constraints: constraints,
    provenance: provenance,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Conversation conversation, {
  List<ConversationWorkflowSpec> confirmed = const [],
  List<String> answered = const [],
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
            body: AwaitingYouSheet(
              currentConversation: conversation,
              onStatusSelected: (_, _) {},
              onAnswerPressed: (question, _) => answered.add(question),
              onConfirmAssumption: confirmed.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('a blocking assumption can be confirmed from here', (
    tester,
  ) async {
    // The claim this slice exists for. Both answering surfaces were complete in
    // source and neither rendered: they were each called exactly once, from
    // inside `_buildWorkflowPanel`, which has had no caller since 2026-04-18.
    final confirmed = <ConversationWorkflowSpec>[];
    await _pump(
      tester,
      _conversation(constraints: const [_claim], provenance: [_mark()]),
      confirmed: confirmed,
    );

    expect(find.textContaining(_claim), findsOneWidget);
    await tester.tap(find.text('Confirm this'));
    await tester.pump();

    expect(confirmed, hasLength(1));
    final item = confirmed.single.provenance.single;
    expect(item.confirmed, isTrue);
    // Confirming clears the block, which is the whole point: it is the state
    // that stops work and the user is the only one who can clear it.
    expect(confirmed.single.blockingAssumptions, isEmpty);
  });

  testWidgets('an open question can be answered from here', (tester) async {
    final answered = <String>[];
    await _pump(
      tester,
      _conversation(openQuestions: const [_question]),
      answered: answered,
    );

    expect(find.text(_question), findsOneWidget);
    await tester.tap(find.text('Answer'));
    await tester.pump();

    expect(answered, equals([_question]));
  });

  testWidgets('a constraint that is not blocking is not listed', (
    tester,
  ) async {
    // Only the waiting items. A plan's constraints already have a surface, and
    // repeating them here would make this a second copy of the contract rather
    // than an answer to "what is stopping work".
    await _pump(
      tester,
      _conversation(
        constraints: const [_claim],
        provenance: [_mark(confirmed: true)],
      ),
    );

    expect(find.textContaining(_claim), findsNothing);
    expect(find.text('Nothing is waiting on you right now.'), findsOneWidget);
  });

  testWidgets('both kinds appear together', (tester) async {
    await _pump(
      tester,
      _conversation(
        openQuestions: const [_question],
        constraints: const [_claim],
        provenance: [_mark()],
      ),
    );

    expect(find.text(_question), findsOneWidget);
    expect(find.textContaining(_claim), findsOneWidget);
    expect(find.text('Unconfirmed assumptions'), findsOneWidget);
  });
}
