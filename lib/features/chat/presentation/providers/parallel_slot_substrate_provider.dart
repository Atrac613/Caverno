import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/llama_cpp_slot_discovery.dart';
import '../../data/datasources/llama_cpp_slot_transport.dart';
import '../../data/datasources/parallel_slot_executor.dart';

/// LL20 extension-preserving chat transport for the active OpenAI-compatible
/// endpoint, or null for the on-device Apple provider (no server slots/cache).
final llamaCppSlotTransportProvider = Provider<LlamaCppSlotTransport?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (settings.llmProvider != LlmProvider.openAiCompatible) return null;
  final transport = LlamaCppSlotTransport(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
  );
  ref.onDispose(transport.close);
  return transport;
});

/// LL20 slot discovery (`GET /slots`) for the active OpenAI-compatible endpoint,
/// or null for the on-device Apple provider.
final llamaCppSlotDiscoveryProvider = Provider<LlamaCppSlotDiscovery?>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (settings.llmProvider != LlmProvider.openAiCompatible) return null;
  final discovery = LlamaCppSlotDiscovery(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
  );
  ref.onDispose(discovery.close);
  return discovery;
});

/// The LL20 parallel slot executor. Stateless, so a single shared instance.
/// LL7 (Best-of-N) and LL13 (parallel worktrees) compose this with the
/// transport and discovery providers to run isolated concurrent candidates.
final parallelSlotExecutorProvider = Provider<ParallelSlotExecutor>(
  (_) => const ParallelSlotExecutor(),
);
