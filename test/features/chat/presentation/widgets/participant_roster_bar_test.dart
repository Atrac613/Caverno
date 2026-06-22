import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/presentation/widgets/participant_roster_bar.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

Future<void> _pumpRoster(
  WidgetTester tester, {
  required List<ConversationParticipant> participants,
  Set<String> referencedParticipantIds = const <String>{},
  ParticipantRosterChanged? onChanged,
}) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.runAsync(() async {
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
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: ParticipantRosterBar(
                    participants: participants,
                    config: const ParticipantTurnConfig(),
                    endpoints: const [],
                    primaryModel: 'primary-model',
                    referencedParticipantIds: referencedParticipantIds,
                    onChanged:
                        onChanged ??
                        ({required participants, required config}) {},
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  });
  await tester.pumpAndSettle();
}

Finder _participantChip(String name) {
  return find.ancestor(of: find.text(name), matching: find.byType(ActionChip));
}

void main() {
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  const primary = ConversationParticipant(
    id: 'primary',
    displayName: 'Primary',
    roleLabel: 'Facilitator',
    order: 0,
  );
  const reviewer = ConversationParticipant(
    id: 'reviewer',
    displayName: 'Reviewer',
    roleLabel: 'Critic',
    endpointId: 'pc2',
    order: 1,
  );

  testWidgets('shows the user and each assistant participant', (tester) async {
    await _pumpRoster(tester, participants: const [primary, reviewer]);

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Reviewer'), findsOneWidget);
    expect(find.text('Facilitator'), findsOneWidget);
    expect(find.text('Critic'), findsOneWidget);
  });

  testWidgets('disables a referenced participant instead of removing it', (
    tester,
  ) async {
    List<ConversationParticipant>? changedParticipants;
    await _pumpRoster(
      tester,
      participants: const [primary, reviewer],
      referencedParticipantIds: const {'reviewer'},
      onChanged: ({required participants, required config}) {
        changedParticipants = participants;
      },
    );

    await tester.tap(_participantChip('Reviewer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    final reviewerAfterRemove = changedParticipants!.singleWhere(
      (participant) => participant.id == 'reviewer',
    );
    expect(reviewerAfterRemove.enabled, isFalse);
    expect(changedParticipants!.map((participant) => participant.id), [
      'primary',
      'reviewer',
    ]);
  });

  testWidgets('removes an unreferenced participant from the roster', (
    tester,
  ) async {
    List<ConversationParticipant>? changedParticipants;
    await _pumpRoster(
      tester,
      participants: const [primary, reviewer],
      onChanged: ({required participants, required config}) {
        changedParticipants = participants;
      },
    );

    await tester.tap(_participantChip('Reviewer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(changedParticipants!.map((participant) => participant.id), [
      'primary',
    ]);
  });
}
