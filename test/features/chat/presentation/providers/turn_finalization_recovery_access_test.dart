import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/reasoning_only_stop.dart';
import 'package:caverno/features/chat/presentation/providers/turn_finalization_state_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final owner = ChatTurnOwner(conversationId: 't', interactionGeneration: 1);
  late TurnFinalizationStateRegistry registry;
  setUp(() {
    registry = TurnFinalizationStateRegistry()..begin(owner);
  });

  test('a reasoning-only stop recovers once without progress', () {
    expect(registry.mayRecoverReasoningOnly(owner, 4), isTrue);
    registry.recordRecovery(owner, ReasoningOnlyStop.recoveryCode, 4);
    expect(
      registry.transforms(owner),
      contains('coding_continuation_recovery_reasoning_only_stop'),
    );
    expect(registry.mayRecoverReasoningOnly(owner, 4), isFalse);
  });

  test('tool progress since the last recovery allows another, up to three', () {
    // Session 49103ed0: a second stop after six productive loops ended the
    // turn with the last edit described instead of made.
    var results = 4;
    for (var recovery = 0; recovery < 3; recovery++) {
      expect(registry.mayRecoverReasoningOnly(owner, results), isTrue);
      registry.recordRecovery(owner, ReasoningOnlyStop.recoveryCode, results);
      results += 6;
    }
    expect(registry.mayRecoverReasoningOnly(owner, results), isFalse);
  });

  test('other recoveries leave the reasoning-only allowance alone', () {
    registry.recordRecovery(owner, 'project_verification_repair', 2);
    expect(
      registry.transforms(owner),
      contains('coding_continuation_recovery_project_verification_repair'),
    );
    expect(registry.mayRecoverReasoningOnly(owner, 2), isTrue);
  });
}
