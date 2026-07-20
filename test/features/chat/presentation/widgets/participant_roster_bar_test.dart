import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/participant_roster_bar.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

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
  List<NamedEndpoint> endpoints = const [],
  Set<String> referencedParticipantIds = const <String>{},
  ParticipantTurnRuntime? runtime,
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
                    endpoints: endpoints,
                    primaryModel: 'primary-model',
                    referencedParticipantIds: referencedParticipantIds,
                    runtime: runtime,
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

Future<void> _tapVisibleText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
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

  testWidgets('shows active participant tool activity', (tester) async {
    await _pumpRoster(
      tester,
      participants: const [primary, reviewer],
      runtime: const ParticipantTurnRuntime(
        activeParticipantId: 'reviewer',
        activeParticipantName: 'Reviewer',
        activeParticipantRoleLabel: 'Critic',
        currentRound: 1,
        maxRounds: 2,
        multiRound: true,
        activeToolName: 'read_file',
      ),
    );

    expect(find.text('Reviewer - round 1/2'), findsOneWidget);
    expect(find.text('Using read_file'), findsOneWidget);
  });

  testWidgets('adds a mesh participant from the invite sheet', (tester) async {
    final endpoint = NamedEndpoint(
      id: NamedEndpoint.buildId('http://pc2.example/v1'),
      label: 'PC2',
      baseUrl: 'http://pc2.example/v1',
    ).normalizedForPersistence();
    List<ConversationParticipant>? changedParticipants;
    await _pumpRoster(
      tester,
      participants: const [],
      endpoints: [endpoint],
      onChanged: ({required participants, required config}) {
        changedParticipants = participants;
      },
    );

    await tester.tap(find.text('Participants'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Senior engineer').last);
    await tester.pumpAndSettle();

    expect(find.text('PC2'), findsOneWidget);

    await tester.tap(find.text('Default permissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto review').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use tools'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(2), 'review-model');
    await _tapVisibleText(tester, 'Save');

    expect(changedParticipants, isNotNull);
    expect(changedParticipants!.map((participant) => participant.endpointId), [
      '',
      endpoint.id,
    ]);

    final addedParticipant = changedParticipants!.last;
    expect(addedParticipant.displayName, 'Senior Engineer');
    expect(addedParticipant.roleLabel, 'Senior Engineer');
    expect(addedParticipant.roleSystemPrompt, contains('senior engineer'));
    expect(addedParticipant.model, 'review-model');
    expect(addedParticipant.facilitatesTurns, isFalse);
    expect(addedParticipant.toolApprovalMode, ToolApprovalMode.autoReview);
    expect(addedParticipant.toolsEnabled, isTrue);
  });

  testWidgets('facilitator preset marks the participant as turn manager', (
    tester,
  ) async {
    final endpoint = NamedEndpoint(
      id: NamedEndpoint.buildId('http://pc2.example/v1'),
      label: 'PC2',
      baseUrl: 'http://pc2.example/v1',
    ).normalizedForPersistence();
    List<ConversationParticipant>? changedParticipants;
    await _pumpRoster(
      tester,
      participants: const [],
      endpoints: [endpoint],
      onChanged: ({required participants, required config}) {
        changedParticipants = participants;
      },
    );

    await tester.tap(find.text('Participants'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Facilitator').last);
    await tester.pumpAndSettle();

    await _tapVisibleText(tester, 'Save');

    expect(changedParticipants, isNotNull);
    final addedParticipant = changedParticipants!.last;
    expect(addedParticipant.displayName, 'Facilitator');
    expect(addedParticipant.roleLabel, 'Facilitator');
    expect(addedParticipant.facilitatesTurns, isTrue);
  });

  testWidgets('legacy facilitator role saves structured turn management', (
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

    await tester.tap(_participantChip('Primary'));
    await tester.pumpAndSettle();
    await _tapVisibleText(tester, 'Save');

    expect(changedParticipants, isNotNull);
    final savedPrimary = changedParticipants!.singleWhere(
      (participant) => participant.id == 'primary',
    );
    expect(savedPrimary.facilitatesTurns, isTrue);
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
    await _tapVisibleText(tester, 'Remove');

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
    await _tapVisibleText(tester, 'Remove');

    expect(changedParticipants!.map((participant) => participant.id), [
      'primary',
    ]);
  });
}
