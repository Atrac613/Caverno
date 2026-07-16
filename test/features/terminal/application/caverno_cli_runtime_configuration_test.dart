import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/application/caverno_cli_runtime_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final persisted = AppSettings.defaults().copyWith(
    baseUrl: 'http://persisted.test/v1',
    model: 'persisted-model',
    apiKey: 'persisted-key',
  );

  test('command flags override environment and persisted settings', () {
    final resolved = resolveCavernoCliRuntimeConfiguration(
      invocation: CavernoCliInvocation.parse(const <String>[
        'chat',
        '--base-url',
        'http://flag.test/v1',
        '--model',
        'flag-model',
        '--api-key',
        'flag-key',
        'hello',
      ]),
      environment: const <String, String>{
        'CAVERNO_LLM_BASE_URL': 'http://environment.test/v1',
        'CAVERNO_LLM_MODEL': 'environment-model',
        'CAVERNO_LLM_API_KEY': 'environment-key',
      },
      persistedSettings: persisted,
    );

    expect(resolved.baseUrl, 'http://flag.test/v1');
    expect(resolved.model, 'flag-model');
    expect(resolved.apiKey, 'flag-key');
  });

  test('environment overrides persisted settings when flags are absent', () {
    final resolved = resolveCavernoCliRuntimeConfiguration(
      invocation: CavernoCliInvocation.parse(const <String>['chat', 'hello']),
      environment: const <String, String>{
        'CAVERNO_LLM_BASE_URL': 'http://environment.test/v1',
        'CAVERNO_LLM_MODEL': 'environment-model',
        'CAVERNO_LLM_API_KEY': 'environment-key',
      },
      persistedSettings: persisted,
    );

    expect(resolved.baseUrl, 'http://environment.test/v1');
    expect(resolved.model, 'environment-model');
    expect(resolved.apiKey, 'environment-key');
  });

  test('persisted settings override built-in defaults', () {
    final resolved = resolveCavernoCliRuntimeConfiguration(
      invocation: CavernoCliInvocation.parse(const <String>['chat', 'hello']),
      environment: const <String, String>{},
      persistedSettings: persisted,
    );

    expect(resolved.baseUrl, persisted.baseUrl);
    expect(resolved.model, persisted.model);
    expect(resolved.apiKey, persisted.apiKey);
  });

  test('blank higher tiers fall back to built-in defaults', () {
    final resolved = resolveCavernoCliRuntimeConfiguration(
      invocation: CavernoCliInvocation.parse(const <String>['chat', 'hello']),
      environment: const <String, String>{
        'CAVERNO_LLM_BASE_URL': '  ',
        'CAVERNO_LLM_MODEL': '',
        'CAVERNO_LLM_API_KEY': '\n',
      },
      persistedSettings: persisted.copyWith(
        baseUrl: '',
        model: ' ',
        apiKey: '',
      ),
    );

    expect(resolved.baseUrl, ApiConstants.defaultBaseUrl);
    expect(resolved.model, ApiConstants.defaultModel);
    expect(resolved.apiKey, ApiConstants.defaultApiKey);
  });
}
