part of 'chat_presentation_widgets_tiny_test.dart';

void _runQueuedMessagesStrip() {
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

  testWidgets('offers interrupt only for steerable messages while running', (
    tester,
  ) async {
    const messages = [
      QueuedChatMessage(
        id: 'queued-text',
        content: 'Use beta instead',
        imageBase64: null,
        imageMimeType: null,
        languageCode: 'en',
        isVoiceMode: false,
        bypassPlanMode: false,
      ),
      QueuedChatMessage(
        id: 'queued-image',
        content: 'Look at this',
        imageBase64: 'base64-image',
        imageMimeType: 'image/png',
        languageCode: 'en',
        isVoiceMode: false,
        bypassPlanMode: false,
      ),
    ];
    final interruptedIds = <String>[];

    Widget strip({ValueChanged<String>? onInterrupt}) => MaterialApp(
      home: Scaffold(
        body: QueuedMessagesStrip(
          messages: messages,
          onRemove: (_) {},
          onInterrupt: onInterrupt,
        ),
      ),
    );

    await tester.pumpWidget(strip());
    expect(find.byTooltip('Interrupt with this message'), findsNothing);

    await tester.pumpWidget(strip(onInterrupt: interruptedIds.add));
    // An image cannot ride a continuation request, so only the text row can.
    expect(find.byTooltip('Interrupt with this message'), findsOneWidget);

    await tester.tap(find.byTooltip('Interrupt with this message'));
    await tester.pump();
    expect(interruptedIds, ['queued-text']);
  });
}
