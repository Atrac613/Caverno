part of 'chat_presentation_providers_tiny_test.dart';

void _runParallelSlotSubstrateProvider() {
  test(
    'composes transport, discovery, and executor for the default endpoint',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final transport = container.read(llamaCppSlotTransportProvider);
      final discovery = container.read(llamaCppSlotDiscoveryProvider);
      final executor = container.read(parallelSlotExecutorProvider);

      expect(transport, isNotNull);
      expect(
        transport!.chatCompletionsUri.toString(),
        'http://localhost:1234/v1/chat/completions',
      );
      expect(discovery, isNotNull);
      // /slots lives at the native root, not under /v1.
      expect(
        discovery!.slotsUri.toString(),
        'http://localhost:1234/slots?model=qwen3.6-27b-mtp-vision',
      );
      expect(executor, isA<ParallelSlotExecutor>());
    },
  );
}
