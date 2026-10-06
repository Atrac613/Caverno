part of 'chat_presentation_providers_tiny_test.dart';

void _runCodingDiagnosticFeedbackProvider() {
  group('codingDiagnosticFeedbackServiceProvider', () {
    test('uses the LSP registry before the analyzer fallback', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(codingDiagnosticFeedbackServiceProvider);

      expect(service, isA<CodingDiagnosticFeedbackService>());
      expect(service.providerName, 'lsp_json_rpc');
    });
  });
}
