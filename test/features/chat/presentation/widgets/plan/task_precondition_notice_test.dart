import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/task_precondition_notice.dart';
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

Future<void> _pump(
  WidgetTester tester,
  List<ConversationTaskPrecondition> unmet,
) async {
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
          home: Scaffold(body: TaskPreconditionNotice(unmet: unmet)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('names each unmet edge by kind and reference', (tester) async {
    await _pump(tester, const [
      ConversationTaskPrecondition(
        kind: ConversationTaskPreconditionKind.task,
        ref: 'Audit the record ids',
      ),
      ConversationTaskPrecondition(
        kind: ConversationTaskPreconditionKind.assumption,
        ref: 'Record ids are stable',
      ),
      ConversationTaskPrecondition(
        kind: ConversationTaskPreconditionKind.question,
        ref: 'Last-write-wins or merge?',
      ),
    ]);

    expect(find.text('Waiting on'), findsOneWidget);
    expect(find.text('• task: Audit the record ids'), findsOneWidget);
    expect(
      find.text('• unconfirmed assumption: Record ids are stable'),
      findsOneWidget,
      reason:
          'Two of the three kinds are things the user can clear themself, so '
          'naming which one is missing is what makes the row actionable.',
    );
    expect(
      find.text('• unanswered question: Last-write-wins or merge?'),
      findsOneWidget,
    );
  });

  testWidgets('a ready task renders nothing at all', (tester) async {
    await _pump(tester, const []);

    expect(find.text('Waiting on'), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
