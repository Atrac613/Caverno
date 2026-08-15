import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/turn_steering_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Message message({
    required String id,
    required MessageRole role,
    bool isStreaming = false,
  }) => Message(
    id: id,
    content: id,
    role: role,
    timestamp: DateTime(2026, 8, 7),
    isStreaming: isStreaming,
  );

  group('canSteer', () {
    test('accepts plain text typed against a running turn', () {
      expect(
        TurnSteeringPolicy.canSteer(
          content: 'use beta instead',
          hasImage: false,
          isVoiceMode: false,
        ),
        isTrue,
      );
    });

    test('rejects what steering cannot carry', () {
      // Each of these falls back to the queue rather than being dropped, so
      // rejecting here costs the user nothing.
      expect(
        TurnSteeringPolicy.canSteer(
          content: '   ',
          hasImage: false,
          isVoiceMode: false,
        ),
        isFalse,
      );
      expect(
        TurnSteeringPolicy.canSteer(
          content: 'look at this',
          hasImage: true,
          isVoiceMode: false,
        ),
        isFalse,
      );
      expect(
        TurnSteeringPolicy.canSteer(
          content: 'stop',
          hasImage: false,
          isVoiceMode: true,
        ),
        isFalse,
      );
    });
  });

  group('insertIndex', () {
    test('lands ahead of the reply still being written', () {
      final messages = [
        message(id: 'user', role: MessageRole.user),
        message(id: 'done', role: MessageRole.assistant),
        message(
          id: 'streaming',
          role: MessageRole.assistant,
          isStreaming: true,
        ),
      ];

      expect(TurnSteeringPolicy.insertIndex(messages), 2);
    });

    test('skips a whole trailing run of streaming messages', () {
      final messages = [
        message(id: 'user', role: MessageRole.user),
        message(id: 'a', role: MessageRole.assistant, isStreaming: true),
        message(id: 'b', role: MessageRole.assistant, isStreaming: true),
      ];

      expect(TurnSteeringPolicy.insertIndex(messages), 1);
    });

    test('appends when nothing is in flight', () {
      final messages = [
        message(id: 'user', role: MessageRole.user),
        message(id: 'done', role: MessageRole.assistant),
      ];

      expect(TurnSteeringPolicy.insertIndex(messages), 2);
      expect(TurnSteeringPolicy.insertIndex(const <Message>[]), 0);
    });
  });

  test('steeringMessage keeps the arrival time, not the commit time', () {
    final receivedAt = DateTime(2026, 8, 7, 10, 30);

    final result = TurnSteeringPolicy.steeringMessage(
      id: 'steer-1',
      content: '  use beta instead  ',
      receivedAt: receivedAt,
    );

    expect(result.id, 'steer-1');
    expect(result.content, 'use beta instead');
    expect(result.role, MessageRole.user);
    // The transcript has to read in the order the user lived through, so the
    // timestamp is when they typed it rather than when a request took it.
    expect(result.timestamp, receivedAt);
  });
}
