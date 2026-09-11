import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/prompt_token_calibration_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatTurnOwner owner(String conversationId, int generation) => ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );

  late PromptTokenCalibrationRegistry registry;

  setUp(() => registry = PromptTokenCalibrationRegistry());

  test('pairs a measurement with the estimate made for that request', () {
    final turn = owner('thread-a', 1);

    registry.recordEstimate(owner: turn, estimatedPromptTokens: 800);
    registry.recordMeasurement(owner: turn, measuredPromptTokens: 8200);

    expect(registry.forConversation('thread-a').uncountedTokens, 7400);
  });

  test('ignores a measurement with no estimate to pair it with', () {
    registry.recordMeasurement(
      owner: owner('thread-a', 1),
      measuredPromptTokens: 8200,
    );

    expect(registry.forConversation('thread-a').hasMeasurement, isFalse);
  });

  test('keeps the largest shortfall, so a tool-free final answer cannot '
      'erase the catalog measured earlier in the same turn', () {
    final turn = owner('thread-a', 1);

    registry.recordEstimate(owner: turn, estimatedPromptTokens: 800);
    registry.recordMeasurement(owner: turn, measuredPromptTokens: 8200);
    // The final answer is sent without tools: a large estimate, a small gap.
    registry.recordEstimate(owner: turn, estimatedPromptTokens: 5000);
    registry.recordMeasurement(owner: turn, measuredPromptTokens: 5400);

    expect(registry.forConversation('thread-a').uncountedTokens, 7400);
  });

  test('adopts a larger shortfall when one is measured', () {
    final turn = owner('thread-a', 1);

    registry.recordEstimate(owner: turn, estimatedPromptTokens: 800);
    registry.recordMeasurement(owner: turn, measuredPromptTokens: 3800);
    registry.recordEstimate(owner: turn, estimatedPromptTokens: 900);
    registry.recordMeasurement(owner: turn, measuredPromptTokens: 9900);

    expect(registry.forConversation('thread-a').uncountedTokens, 9000);
  });

  test('keeps threads isolated', () {
    registry.recordEstimate(
      owner: owner('thread-a', 1),
      estimatedPromptTokens: 800,
    );
    registry.recordMeasurement(
      owner: owner('thread-a', 1),
      measuredPromptTokens: 8200,
    );

    expect(registry.forConversation('thread-b').hasMeasurement, isFalse);
  });

  test('a measurement cannot complete another thread\'s pending estimate', () {
    registry.recordEstimate(
      owner: owner('thread-a', 1),
      estimatedPromptTokens: 800,
    );
    registry.recordMeasurement(
      owner: owner('thread-b', 1),
      measuredPromptTokens: 8200,
    );

    expect(registry.forConversation('thread-b').hasMeasurement, isFalse);
    expect(registry.forConversation('thread-a').hasMeasurement, isFalse);
  });

  test('drops pending estimates from superseded generations', () {
    registry.recordEstimate(
      owner: owner('thread-a', 1),
      estimatedPromptTokens: 800,
    );
    registry.recordEstimate(
      owner: owner('thread-a', 2),
      estimatedPromptTokens: 900,
    );
    registry.recordMeasurement(
      owner: owner('thread-a', 1),
      measuredPromptTokens: 8200,
    );

    expect(registry.forConversation('thread-a').hasMeasurement, isFalse);
  });

  test('returns an empty calibration for a null conversation', () {
    expect(registry.forConversation(null).hasMeasurement, isFalse);
  });

  test('clearConversation drops the thread state', () {
    final turn = owner('thread-a', 1);
    registry.recordEstimate(owner: turn, estimatedPromptTokens: 800);
    registry.recordMeasurement(owner: turn, measuredPromptTokens: 8200);

    registry.clearConversation('thread-a');

    expect(registry.forConversation('thread-a').hasMeasurement, isFalse);
  });
}
