import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/chat/data/datasources/parallel_slot_executor.dart';
import 'package:caverno/features/chat/presentation/providers/parallel_slot_substrate_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
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
      expect(discovery!.slotsUri.toString(), 'http://localhost:1234/slots');
      expect(executor, isA<ParallelSlotExecutor>());
    },
  );
}
