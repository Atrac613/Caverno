import '../../../core/utils/logger.dart';
import '../domain/entities/local_model_lifecycle.dart';

/// `[LL9]` request/result/exception lines for a managed-model lifecycle action.
///
/// Load, unload, and pull all log the same three moments, and the triage value
/// is in that shape staying identical across providers — so the wording lives
/// in one place rather than beside each transport.
abstract final class ModelLifecycleActionLog {
  static void request({
    required String actionLabel,
    required String modelId,
    required Uri uri,
    required String payloadLabel,
  }) {
    appLog(
      '[LL9] Model lifecycle $actionLabel request: '
      'model="$modelId", uri=$uri, payload=$payloadLabel',
    );
  }

  static void result({
    required String actionLabel,
    required String modelId,
    required Uri uri,
    required LocalModelLifecycleActionResult result,
  }) {
    final statusCode = result.statusCode == null
        ? ''
        : ', statusCode=${result.statusCode}';
    appLog(
      '[LL9] Model lifecycle $actionLabel result: '
      'model="$modelId", uri=$uri, '
      'supported=${result.supported}, succeeded=${result.succeeded}'
      '$statusCode, message=${result.message}',
    );
  }

  static void exception({
    required String actionLabel,
    required String modelId,
    required Uri uri,
    required Object error,
  }) {
    appLog(
      '[LL9] Model lifecycle $actionLabel exception: '
      'model="$modelId", uri=$uri, error=${error.runtimeType}: $error',
    );
  }
}
