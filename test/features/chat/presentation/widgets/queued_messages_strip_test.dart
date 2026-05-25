import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/queued_messages_strip.dart';

void main() {
  testWidgets('shows queued messages and removes a selected item', (
    tester,
  ) async {
    final removedIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QueuedMessagesStrip(
            messages: const [
              QueuedChatMessage(
                id: 'queued-1',
                content: 'Run the next check',
                imageBase64: null,
                imageMimeType: null,
                languageCode: 'en',
                isVoiceMode: false,
                bypassPlanMode: false,
              ),
              QueuedChatMessage(
                id: 'queued-2',
                content: '',
                imageBase64: 'base64-image',
                imageMimeType: 'image/png',
                languageCode: 'en',
                isVoiceMode: false,
                bypassPlanMode: false,
              ),
            ],
            onRemove: removedIds.add,
          ),
        ),
      ),
    );

    expect(find.text('Queued'), findsNWidgets(2));
    expect(find.text('Run the next check'), findsOneWidget);
    expect(find.text('Image message'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove queued message').first);
    await tester.pump();

    expect(removedIds, ['queued-1']);
  });
}
