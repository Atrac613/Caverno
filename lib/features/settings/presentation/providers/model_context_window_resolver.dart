import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import 'model_list_provider.dart';

/// Context window for the active model, or 0 when neither the endpoint nor the
/// bundled published specs know one.
///
/// Used by both capability-probe paths so a stored profile carries a real
/// context budget instead of the hard-coded zero it used to persist. Preference
/// order is what the serving stack reports (llama.cpp `n_ctx`, LM Studio loaded
/// context, Ollama `num_ctx`) and then the vendor's published figure for cloud
/// models that advertise none — never an estimate, so an unknown model yields 0
/// and downstream consumers simply omit the budget.
///
/// The Apple Foundation Models provider has no model catalog to query.
Future<int> resolveUsableContextTokens(Ref ref, AppSettings settings) async {
  if (settings.llmProvider == LlmProvider.appleFoundationModels) return 0;
  final model = settings.effectiveModel.trim();
  if (model.isEmpty) return 0;

  final tokens = await ref.read(
    modelContextWindowProvider(
      ModelListConfig(
        baseUrl: settings.baseUrl,
        apiKey: settings.apiKey,
        selectedModelId: model,
      ),
    ).future,
  );
  return tokens != null && tokens > 0 ? tokens : 0;
}
