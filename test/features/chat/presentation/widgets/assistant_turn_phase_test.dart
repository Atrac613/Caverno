import 'package:caverno/features/chat/presentation/widgets/assistant_turn_phase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('assistantTurnPhaseFor', () {
    test('reads an empty placeholder as thinking', () {
      expect(assistantTurnPhaseFor(''), AssistantTurnPhase.thinking);
      expect(assistantTurnPhaseFor('   \n'), AssistantTurnPhase.thinking);
    });

    test('reads a trailing tool marker as running tools', () {
      expect(
        assistantTurnPhaseFor('<tool_use>{"name":"read_file"}</tool_use>\n'),
        AssistantTurnPhase.runningTools,
      );
      expect(
        assistantTurnPhaseFor('Checking.\n<tool_call>{"name":"x"}</tool_call>'),
        AssistantTurnPhase.runningTools,
      );
    });

    test('lets a recovery think block after a tool win', () {
      expect(
        assistantTurnPhaseFor('<tool_use>{}</tool_use>\n<think>partial'),
        AssistantTurnPhase.thinking,
      );
    });

    test('reads a closed think block followed by prose as responding', () {
      expect(
        assistantTurnPhaseFor('<think>done</think>\nHere is the answer'),
        AssistantTurnPhase.responding,
      );
    });

    test('reads an unclosed reasoning tag as thinking', () {
      expect(
        assistantTurnPhaseFor('<thinking>still going'),
        AssistantTurnPhase.thinking,
      );
      expect(
        assistantTurnPhaseFor('<thought>still going'),
        AssistantTurnPhase.thinking,
      );
    });

    test('does not treat a bare closing tag as an open block', () {
      expect(
        assistantTurnPhaseFor('</think>\nAnswer'),
        AssistantTurnPhase.responding,
      );
    });

    test('reads plain streamed prose as responding', () {
      expect(
        assistantTurnPhaseFor('Here is what I found'),
        AssistantTurnPhase.responding,
      );
    });
  });
}
