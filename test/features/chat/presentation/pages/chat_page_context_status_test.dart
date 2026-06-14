import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/context_surgery_observation_service.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

void main() {
  test('does not show the context status widget for an empty chat', () {
    expect(
      shouldShowContextStatusWidget(
        const ChatState(messages: [], isLoading: false),
      ),
      isFalse,
    );
  });

  test('keeps the context status widget visible for image-only messages', () {
    expect(
      shouldShowContextStatusWidget(
        ChatState(
          messages: [
            Message(
              id: 'image-message',
              content: '',
              role: MessageRole.user,
              timestamp: DateTime(2026, 6, 5),
              imageBase64: 'image-data',
              imageMimeType: 'image/png',
            ),
          ],
          isLoading: true,
        ),
      ),
      isTrue,
    );
  });

  test('shows the context status widget when token usage is available', () {
    expect(
      shouldShowContextStatusWidget(
        const ChatState(messages: [], isLoading: false, promptTokens: 1200),
      ),
      isTrue,
    );
  });

  test('shows the context status widget when LL14 snapshot is available', () {
    expect(
      shouldShowContextStatusWidget(
        const ChatState(
          messages: [],
          isLoading: false,
          contextSurgerySnapshot: ContextSurgeryObservationSnapshot(
            sections: [
              ContextSurgerySectionSummary(
                kind: ContextSurgeryBlockKind.systemPrompt,
                label: 'System prompt',
                blockCount: 1,
                charCount: 400,
              ),
            ],
          ),
        ),
      ),
      isTrue,
    );
  });
}
