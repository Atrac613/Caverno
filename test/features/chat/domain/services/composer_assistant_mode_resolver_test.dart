import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/services/composer_assistant_mode_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

AssistantMode _resolve({
  AssistantMode settingsMode = AssistantMode.plan,
  bool isPlanningSession = false,
  bool isCodingWorkspace = true,
  bool hasConversation = true,
}) {
  return ComposerAssistantModeResolver.resolve(
    settingsMode: settingsMode,
    isPlanningSession: isPlanningSession,
    isCodingWorkspace: isCodingWorkspace,
    hasConversation: hasConversation,
  );
}

void main() {
  test('a planning session always shows plan', () {
    expect(
      _resolve(settingsMode: AssistantMode.coding, isPlanningSession: true),
      AssistantMode.plan,
    );
  });

  test(
    'a pending plan pick stays visible on a thread that has not started',
    () {
      expect(
        _resolve(hasConversation: false),
        AssistantMode.plan,
        reason: 'the next send turns this preference into a planning session',
      );
    },
  );

  test('a stored plan preference reads as coding inside a normal thread', () {
    expect(_resolve(), AssistantMode.coding);
  });

  test('plan is unavailable outside a coding workspace', () {
    expect(
      _resolve(isCodingWorkspace: false, hasConversation: false),
      AssistantMode.general,
    );
  });

  test('other modes pass through untouched', () {
    for (final mode in [AssistantMode.general, AssistantMode.coding]) {
      expect(_resolve(settingsMode: mode, hasConversation: false), mode);
    }
  });
}
