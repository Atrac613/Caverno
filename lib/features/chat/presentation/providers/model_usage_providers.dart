import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/drift_model_usage_store.dart';
import '../../domain/entities/model_usage_sink.dart';
import 'semantic_search_provider.dart';

/// Per-model token usage store, or null when drift is unavailable (the Hive
/// fallback path), in which case usage is simply not recorded.
final driftModelUsageStoreProvider = Provider<DriftModelUsageStore?>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database == null ? null : DriftModelUsageStore(database);
});

/// The sink handed to the chat data source. Null when there is nowhere to
/// record to, so the data source skips the work entirely.
final modelUsageSinkProvider = Provider<ModelUsageSink?>(
  (ref) => ref.watch(driftModelUsageStoreProvider),
);
