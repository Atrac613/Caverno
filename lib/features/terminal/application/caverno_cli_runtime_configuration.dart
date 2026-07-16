import '../../../../core/constants/api_constants.dart';
import '../../settings/domain/entities/app_settings.dart';
import 'caverno_cli_arguments.dart';

/// Effective OpenAI-compatible configuration for one terminal invocation.
final class CavernoCliRuntimeConfiguration {
  const CavernoCliRuntimeConfiguration({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
}

/// Resolves flags, environment, persisted settings, then built-in defaults.
CavernoCliRuntimeConfiguration resolveCavernoCliRuntimeConfiguration({
  required CavernoCliInvocation invocation,
  required Map<String, String> environment,
  required AppSettings persistedSettings,
}) {
  return CavernoCliRuntimeConfiguration(
    baseUrl: _firstNonEmpty(<String?>[
      invocation.baseUrl,
      environment['CAVERNO_LLM_BASE_URL'],
      persistedSettings.baseUrl,
      ApiConstants.defaultBaseUrl,
    ]),
    model: _firstNonEmpty(<String?>[
      invocation.model,
      environment['CAVERNO_LLM_MODEL'],
      persistedSettings.model,
      ApiConstants.defaultModel,
    ]),
    apiKey: _firstNonEmpty(<String?>[
      invocation.apiKey,
      environment['CAVERNO_LLM_API_KEY'],
      persistedSettings.apiKey,
      ApiConstants.defaultApiKey,
    ]),
  );
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}
