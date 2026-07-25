import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/presentation/coordinators/composer_assistant_mode_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingConversationsNotifier extends ConversationsNotifier {
  _RecordingConversationsNotifier(this.operations);

  final List<String> operations;

  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Future<void> enterPlanningSession() async => operations.add('enter-plan');

  @override
  Future<void> exitPlanningSession() async => operations.add('exit-plan');
}

class _Harness {
  _Harness() {
    coordinator = ComposerAssistantModeCoordinator(
      conversationsNotifier: _RecordingConversationsNotifier(operations),
      updateAssistantMode: (mode) async => operations.add('mode:${mode.name}'),
      dismissPlanProposal: () => operations.add('dismiss-plan'),
    );
  }

  final List<String> operations = [];
  late final ComposerAssistantModeCoordinator coordinator;

  Future<void> select(
    AssistantMode mode, {
    bool isCodingWorkspace = true,
    bool hasConversation = true,
    bool isPlanningSession = false,
  }) {
    return coordinator.select(
      mode,
      isCodingWorkspace: isCodingWorkspace,
      hasConversation: hasConversation,
      isPlanningSession: isPlanningSession,
    );
  }
}

void main() {
  test(
    'picking plan on a thread that has not started only stores it',
    () async {
      final harness = _Harness();

      await harness.select(AssistantMode.plan, hasConversation: false);

      expect(
        harness.operations,
        ['mode:plan'],
        reason:
            'the planning session must wait for send so the composer keeps the '
            'typed input on the new-thread screen',
      );
    },
  );

  test(
    'picking plan on a started coding thread switches immediately',
    () async {
      final harness = _Harness();

      await harness.select(AssistantMode.plan);

      expect(harness.operations, ['enter-plan']);
    },
  );

  test('plan is refused outside a coding workspace', () async {
    final harness = _Harness();

    await harness.select(
      AssistantMode.plan,
      isCodingWorkspace: false,
      hasConversation: false,
    );

    expect(harness.operations, isEmpty);
  });

  test('leaving plan mode exits the session and drops the proposal', () async {
    final harness = _Harness();

    await harness.select(AssistantMode.coding, isPlanningSession: true);

    expect(harness.operations, ['exit-plan', 'dismiss-plan', 'mode:coding']);
  });

  test('switching between non-plan modes leaves the session alone', () async {
    final harness = _Harness();

    await harness.select(AssistantMode.general);

    expect(harness.operations, ['mode:general']);
  });
}
