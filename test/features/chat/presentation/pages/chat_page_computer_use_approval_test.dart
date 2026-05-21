import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

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

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      demoMode: false,
      mcpEnabled: false,
    );
  }
}

class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();
}

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _ComputerUseApprovalTestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();

  void showPending(PendingComputerUseAction pending) {
    state = state.copyWith(pendingComputerUseAction: pending);
  }
}

class _FakeMacosComputerUseService extends MacosComputerUseService {
  @override
  Future<String> stopHelperWork() async => '{"ok":true}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets(
    'Computer Use approval sheet scrolls long review content without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          chatNotifierProvider.overrideWith(
            _ComputerUseApprovalTestChatNotifier.new,
          ),
          macosComputerUseServiceProvider.overrideWithValue(
            _FakeMacosComputerUseService(),
          ),
          routineSchedulerProvider.overrideWith(RoutineSchedulerController.new),
        ],
      );
      addTearDown(container.dispose);

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
              return UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: const ChatPage(),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsOneWidget);

      final pending = _buildLongComputerUseAction();
      final notifier =
          container.read(chatNotifierProvider.notifier)
              as _ComputerUseApprovalTestChatNotifier;
      notifier.showPending(pending);

      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('computer-use-approval-scroll')),
        findsOneWidget,
      );
      expect(find.text('Deny'), findsOneWidget);
      expect(
        tester.getRect(find.text('Deny')).bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );

      await tester.scrollUntilVisible(
        find.text('Model reason detail 35: verify scroll behavior'),
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('computer-use-approval-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Model reason detail 35: verify scroll behavior'),
        findsOneWidget,
      );
      expect(find.text('Deny'), findsOneWidget);

      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();

      final decision = await pending.completer.future.timeout(
        const Duration(seconds: 1),
      );
      expect(decision.approved, isFalse);
    },
  );
}

PendingComputerUseAction _buildLongComputerUseAction() {
  return PendingComputerUseAction(
    id: 'pending-scroll-test',
    toolName: 'computer_press_key',
    title: 'Approve Key Press',
    riskCategory: 'input',
    riskLabel: 'Input Control',
    warningMessage:
        'This action can focus windows, move the pointer, click, scroll, or send keyboard input on your Mac.',
    approveLabel: 'Approve Key Press',
    requiresUserApproval: true,
    requiresSmokeArming: true,
    emergencyStop: false,
    summary: 'Press command+space',
    details: List<String>.generate(
      40,
      (index) => 'Model reason detail ${index + 1}: verify scroll behavior',
    ),
    targetSummary:
        'Review the keyboard shortcut target "command+space" before approving.',
    targetDetails: const [
      'Role: keyboard_shortcut',
      'Label: command+space',
      'Intended action: press_key',
    ],
    exactTextPreview: null,
    exactTextLength: null,
    approvalBoundaries: const ['target'],
    approvalBlockerCodes: const [],
    actionProposalNextAction:
        'Ask the user to approve the exact target before acting.',
    visionObservationSummary:
        'Verify this action against the latest vision observation before approving.',
    visionObservationDetails: const [],
    reason: 'Open Spotlight to launch Safari.',
    completer: Completer<ComputerUseActionApprovalDecision>(),
  );
}
