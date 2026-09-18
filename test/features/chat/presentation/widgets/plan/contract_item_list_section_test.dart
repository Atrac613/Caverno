import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/presentation/widgets/plan/contract_item_list_section.dart';
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

const _claim = 'Existing entities have stable UUIDs';
const _provenanceService = ConversationContractProvenanceService();

ConversationWorkflowSpec _spec({
  bool assumption = true,
  bool material = true,
  bool confirmed = false,
  String clarificationQuestion = '',
}) {
  return ConversationWorkflowSpec(
    constraints: const [_claim],
    provenance: [
      ConversationContractItemProvenance(
        itemId: _provenanceService.itemId(
          kind: ConversationContractItemKind.constraint,
          value: _claim,
        ),
        kind: ConversationContractItemKind.constraint,
        assumption: assumption,
        material: material,
        confirmed: confirmed,
        clarificationQuestion: clarificationQuestion,
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  ConversationWorkflowSpec? spec,
  void Function(ConversationWorkflowSpec confirmedSpec)? onConfirmAssumption,
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
            body: ContractItemListSection(
              label: 'Constraints',
              items: const [_claim],
              spec: spec,
              kind: spec == null
                  ? null
                  : ConversationContractItemKind.constraint,
              onConfirmAssumption: onConfirmAssumption,
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

  testWidgets('an unconfirmed material assumption says work is paused', (
    tester,
  ) async {
    await _pump(tester, spec: _spec());

    expect(find.text('• $_claim'), findsOneWidget);
    expect(
      find.text('Assumed — work pauses until you confirm this'),
      findsOneWidget,
      reason:
          'ANA0 requires that a material assumption is never presented as a '
          'fact, and this list is where the user reads the contract.',
    );
  });

  testWidgets('a confirmed assumption says who settled it', (tester) async {
    await _pump(tester, spec: _spec(confirmed: true));

    expect(find.text('Assumed — you confirmed this'), findsOneWidget);
    expect(
      find.text('Assumed — work pauses until you confirm this'),
      findsNothing,
    );
  });

  testWidgets('a non-material assumption is marked without alarm', (
    tester,
  ) async {
    await _pump(tester, spec: _spec(material: false));

    expect(
      find.text('Assumed, not verified'),
      findsOneWidget,
      reason:
          'A plain (assumed) mark does not block, so it must not read as if '
          'it does — the distinction is what PR 3e measured.',
    );
  });

  testWidgets('an item with no mark renders exactly as it used to', (
    tester,
  ) async {
    await _pump(tester, spec: _spec(assumption: false));

    expect(find.text('• $_claim'), findsOneWidget);
    expect(find.textContaining('Assumed'), findsNothing);
  });

  testWidgets('a draft list with no provenance marks nothing', (tester) async {
    await _pump(tester);

    expect(find.text('• $_claim'), findsOneWidget);
    expect(find.textContaining('Assumed'), findsNothing);
  });

  testWidgets('a blocking assumption offers the way to clear it', (
    tester,
  ) async {
    final confirmed = <ConversationWorkflowSpec>[];
    await _pump(
      tester,
      spec: _spec(clarificationQuestion: 'Are the UUIDs actually stable?'),
      onConfirmAssumption: confirmed.add,
    );

    expect(
      find.text('Are the UUIDs actually stable?'),
      findsOneWidget,
      reason:
          'The clarification question was already on the mark and was being '
          'discarded here, so the claim was shown without the question that '
          'settles it.',
    );

    await tester.tap(find.text('Confirm this'));
    await tester.pumpAndSettle();

    expect(
      confirmed,
      hasLength(1),
      reason:
          'confirmMaterialAssumption had exactly one caller — the gate, which '
          'only runs once a mutation is already blocked. Without a control '
          'here a dismissed interrupt left no route back.',
    );
    expect(
      confirmed.single.blockingAssumptions,
      isEmpty,
      reason:
          'The spec handed to the page is the confirmed one, so persisting it '
          'is all that is left to do — a callback that only named the item '
          'would leave the transform to be repeated at every call site.',
    );
  });

  testWidgets('a confirmed assumption offers nothing to confirm', (
    tester,
  ) async {
    await _pump(
      tester,
      spec: _spec(confirmed: true, clarificationQuestion: 'Still true?'),
      onConfirmAssumption: (_) {},
    );

    expect(find.text('Confirm this'), findsNothing);
    expect(
      find.text('Still true?'),
      findsNothing,
      reason: 'A settled assumption is not asking anything.',
    );
  });

  testWidgets('a draft list is blocked from confirming what it cannot save', (
    tester,
  ) async {
    await _pump(tester, spec: _spec(clarificationQuestion: 'Is it stable?'));

    expect(
      find.text('Confirm this'),
      findsNothing,
      reason:
          'Without a callback there is no live spec to persist onto, so the '
          'button would be a dead end.',
    );
  });
}
