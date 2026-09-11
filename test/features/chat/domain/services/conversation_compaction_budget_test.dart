import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Message> buildMessages(int count) {
    return List<Message>.generate(count, (index) {
      final isUser = index.isEven;
      return Message(
        id: 'message-$index',
        content: '${isUser ? 'User' : 'Assistant'} turn $index.',
        role: isUser ? MessageRole.user : MessageRole.assistant,
        timestamp: DateTime(2026, 9, 11, 12, index),
      );
    });
  }

  /// A tool-bearing request: the catalog the estimator never walks dwarfs the
  /// message text it does.
  const catalogSizedCalibration = PromptTokenCalibration(
    measuredPromptTokens: 7600,
    estimatedPromptTokens: 200,
  );

  group('PromptTokenCalibration', () {
    test('reports what the estimator failed to count', () {
      expect(catalogSizedCalibration.hasMeasurement, isTrue);
      expect(catalogSizedCalibration.uncountedTokens, 7400);
    });

    test('clamps an over-counting estimator to zero', () {
      const calibration = PromptTokenCalibration(
        measuredPromptTokens: 900,
        estimatedPromptTokens: 1000,
      );

      expect(calibration.uncountedTokens, 0);
    });

    test('treats a missing half of the pair as no measurement', () {
      expect(PromptTokenCalibration.empty.hasMeasurement, isFalse);
      expect(PromptTokenCalibration.empty.uncountedTokens, 0);
      expect(
        const PromptTokenCalibration(
          measuredPromptTokens: 5000,
          estimatedPromptTokens: 0,
        ).uncountedTokens,
        0,
      );
    });
  });

  group('resolvePromptTokenBudget', () {
    test('falls back to the fixed budget when the window is unknown', () {
      expect(
        ConversationCompactionService.resolvePromptTokenBudget(
          usableContextTokens: 0,
          maxResponseTokens: 4096,
        ),
        ConversationCompactionService.maxEstimatedPromptTokens,
      );
    });

    test('reserves the response allowance and a safety margin', () {
      expect(
        ConversationCompactionService.resolvePromptTokenBudget(
          usableContextTokens: 32768,
          maxResponseTokens: 4096,
        ),
        32768 - 4096 - ConversationCompactionService.contextSafetyMarginTokens,
      );
    });

    test('floors a window that barely exceeds its own response allowance', () {
      expect(
        ConversationCompactionService.resolvePromptTokenBudget(
          usableContextTokens: 4096,
          maxResponseTokens: 4096,
        ),
        ConversationCompactionService.minimumPromptTokenBudget,
      );
    });
  });

  group('projectPromptTokens', () {
    test('adds the measured shortfall to the estimate', () {
      final messages = buildMessages(10);
      final estimate = ConversationCompactionService.estimatePromptTokens(
        messages,
      );

      expect(
        ConversationCompactionService.projectPromptTokens(
          messages: messages,
          calibration: catalogSizedCalibration,
        ),
        estimate + 7400,
      );
    });

    test('equals the raw estimate without a measurement', () {
      final messages = buildMessages(10);

      expect(
        ConversationCompactionService.projectPromptTokens(messages: messages),
        ConversationCompactionService.estimatePromptTokens(messages),
      );
    });
  });

  group('assessTokenPressure', () {
    test('reads a short transcript as critical once the catalog is counted',
        () {
      final messages = buildMessages(10);

      final uncalibrated = ConversationCompactionService.assessTokenPressure(
        messages: messages,
      );
      final calibrated = ConversationCompactionService.assessTokenPressure(
        messages: messages,
        calibration: catalogSizedCalibration,
      );

      expect(uncalibrated.level, ConversationTokenPressureLevel.normal);
      expect(calibrated.level, ConversationTokenPressureLevel.critical);
      expect(calibrated.shouldAutoCompact, isTrue);
      expect(
        calibrated.estimatedPromptTokens,
        greaterThan(uncalibrated.estimatedPromptTokens),
      );
    });

    test('reports the resolved budget it judged against', () {
      final pressure = ConversationCompactionService.assessTokenPressure(
        messages: buildMessages(4),
        promptTokenBudget: 27648,
      );

      expect(pressure.promptTokenBudget, 27648);
      expect(pressure.level, ConversationTokenPressureLevel.normal);
    });
  });

  group('shouldCompact', () {
    test('keeps the message-count rule while the prompt size is unknown', () {
      expect(ConversationCompactionService.shouldCompact(buildMessages(16)),
          isTrue);
    });

    test('keeps the message-count rule when the window is known but '
        'nothing has been measured yet', () {
      expect(
        ConversationCompactionService.shouldCompact(
          buildMessages(16),
          promptTokenBudget: 100000,
        ),
        isTrue,
      );
    });

    test('lets a measured thread keep history the model can still hold', () {
      expect(
        ConversationCompactionService.shouldCompact(
          buildMessages(16),
          promptTokenBudget: 100000,
          calibration: const PromptTokenCalibration(
            measuredPromptTokens: 9000,
            estimatedPromptTokens: 8000,
          ),
        ),
        isFalse,
      );
    });

    test('compacts a short transcript whose real prompt is already over', () {
      expect(
        ConversationCompactionService.shouldCompact(
          buildMessages(10),
          promptTokenBudget:
              ConversationCompactionService.maxEstimatedPromptTokens,
          calibration: catalogSizedCalibration,
        ),
        isTrue,
      );
    });

    test('never compacts below the retained-message floor', () {
      expect(
        ConversationCompactionService.shouldCompact(
          buildMessages(ConversationCompactionService.recentMessagesToKeep),
          calibration: catalogSizedCalibration,
        ),
        isFalse,
      );
    });
  });

  test('buildArtifact honors a budget the measured prompt fits inside', () {
    expect(
      ConversationCompactionService.buildArtifact(
        messages: buildMessages(16),
        promptTokenBudget: 100000,
        calibration: const PromptTokenCalibration(
          measuredPromptTokens: 9000,
          estimatedPromptTokens: 8000,
        ),
      ),
      isNull,
    );
  });
}
