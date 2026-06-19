import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/coding_diagnostic_feedback_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';

void main() {
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
