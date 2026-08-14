import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/apple_foundation_models_datasource.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/demo_datasource.dart';
import '../../data/datasources/llm_session_log_store.dart';
import 'model_usage_providers.dart';

/// Creates a chat data source from an immutable settings snapshot.
typedef ChatDataSourceFactory = ChatDataSource Function(AppSettings settings);

final chatDataSourceFactoryProvider = Provider<ChatDataSourceFactory>((ref) {
  final usageSink = ref.watch(modelUsageSinkProvider);
  return (settings) {
    if (settings.demoMode) {
      return DemoDataSource();
    }
    if (settings.llmProvider == LlmProvider.appleFoundationModels) {
      return AppleFoundationModelsDataSource(enableSafePromptRetry: true);
    }
    return ChatRemoteDataSource(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      reasoningEffort: settings.reasoningEffort.apiValue,
      usageSink: usageSink,
      endpointId: settings.activeLlmEndpointId,
      usageLabelResolver: () => LlmSessionLogContext.current?.requestLabel,
    );
  };
});

/// The chat data source for the active provider and endpoint.
///
/// Only the real remote source records per-model usage; demo and on-device
/// providers report no token counts to account for.
final chatRemoteDataSourceProvider = Provider<ChatDataSource>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  return ref.watch(chatDataSourceFactoryProvider)(settings);
});

typedef PrimaryRouteEndpointDataSourceFactory =
    ChatDataSource Function({
      required String baseUrl,
      required String apiKey,
      required String endpointId,
    });

final primaryRouteEndpointDataSourceFactoryProvider =
    Provider<PrimaryRouteEndpointDataSourceFactory>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      final usageSink = ref.watch(modelUsageSinkProvider);
      return ({
        required String baseUrl,
        required String apiKey,
        required String endpointId,
      }) => ChatRemoteDataSource(
        baseUrl: baseUrl,
        apiKey: apiKey,
        reasoningEffort: settings.reasoningEffort.apiValue,
        usageSink: usageSink,
        endpointId: endpointId,
        usageLabelResolver: () => LlmSessionLogContext.current?.requestLabel,
      );
    });
