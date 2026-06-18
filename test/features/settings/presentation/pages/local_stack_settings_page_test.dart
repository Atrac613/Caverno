import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/data/model_remote_datasource.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/local_host_resources.dart';
import 'package:caverno/features/settings/presentation/pages/local_stack_settings_page.dart';
import 'package:caverno/features/settings/presentation/providers/local_model_lifecycle_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('loads an unloaded router model and refreshes status', (
    tester,
  ) async {
    var loaded = false;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/models') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'alpha-model',
                'status': {'value': loaded ? 'loaded' : 'unloaded'},
                'metadata': {'n_ctx': 4096},
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/models/load') {
        loaded = true;
        return http.Response('{"success":true}', 200);
      }
      return http.Response('not found', 404);
    });

    await _pumpPage(tester, client: client);

    expect(find.text('alpha-model'), findsOneWidget);
    expect(find.textContaining('Unloaded'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('local-stack-load-alpha-model')),
    );
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request.url.path == '/models/load'),
      hasLength(1),
    );
    expect(
      requests
          .singleWhere((request) => request.url.path == '/models/load')
          .body,
      '{"model":"alpha-model"}',
    );
    expect(find.textContaining('Loaded'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('local-stack-unload-alpha-model')),
      findsOneWidget,
    );
  });

  testWidgets('unloads a loaded router model', (tester) async {
    var loaded = true;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/models') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'beta-model',
                'status': {'value': loaded ? 'loaded' : 'unloaded'},
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/models/unload') {
        loaded = false;
        return http.Response('{"success":true}', 200);
      }
      return http.Response('not found', 404);
    });

    await _pumpPage(tester, client: client);

    expect(
      find.byKey(const ValueKey('local-stack-unload-beta-model')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('local-stack-unload-beta-model')),
    );
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request.url.path == '/models/unload'),
      hasLength(1),
    );
    expect(
      requests
          .singleWhere((request) => request.url.path == '/models/unload')
          .body,
      '{"model":"beta-model"}',
    );
    expect(find.textContaining('Unloaded'), findsOneWidget);
  });

  testWidgets('shows unsupported message for non-router endpoints', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return http.Response('not supported', 501);
    });

    await _pumpPage(tester, client: client);

    expect(find.textContaining('Use llama.cpp router mode'), findsOneWidget);
    expect(find.byKey(const ValueKey('local-stack-refresh')), findsOneWidget);
  });

  testWidgets('prepares explicit primary endpoint role models', (tester) async {
    var smallLoaded = false;
    final requests = <http.Request>[];
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      memoryExtractionModel: 'small-model',
      subagentModel: 'small-model',
      goalSuggestionModel: 'mesh-model',
      goalSuggestionEndpointId: 'http://mesh-box:1234/v1',
      approvalAutoReviewModel: 'review-model',
    );
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/models') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'small-model',
                'status': {'value': smallLoaded ? 'loaded' : 'unloaded'},
              },
              {
                'id': 'review-model',
                'status': {'value': 'loaded'},
              },
              {
                'id': 'mesh-model',
                'status': {'value': 'unloaded'},
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/models/load') {
        smallLoaded = true;
        return http.Response('{"success":true}', 200);
      }
      return http.Response('not found', 404);
    });

    await _pumpPage(tester, client: client, settings: settings);

    expect(
      find.text('1 of 2 role models need loading on this endpoint.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('local-stack-prepare-role-models')),
    );
    await tester.pumpAndSettle();

    final loadRequests = requests
        .where((request) => request.url.path == '/models/load')
        .toList();
    expect(loadRequests, hasLength(1));
    expect(loadRequests.single.body, '{"model":"small-model"}');
    expect(
      find.textContaining('Role models prepared: 1 loaded'),
      findsOneWidget,
    );
  });

  testWidgets('selects a named endpoint and prepares its role models', (
    tester,
  ) async {
    const meshUrl = 'http://mesh-box:1234/v1';
    final meshEndpoint = NamedEndpoint(
      id: NamedEndpoint.buildId(meshUrl),
      label: 'Mesh Box',
      baseUrl: meshUrl,
    ).normalizedForPersistence();
    var meshLoaded = false;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/models') {
        final modelId = request.url.host == 'mesh-box'
            ? 'mesh-subagent'
            : 'primary-model';
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': modelId,
                'status': {
                  'value': request.url.host == 'mesh-box' && meshLoaded
                      ? 'loaded'
                      : 'unloaded',
                },
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/models/load') {
        if (request.url.host == 'mesh-box') {
          meshLoaded = true;
        }
        return http.Response('{"success":true}', 200);
      }
      return http.Response('not found', 404);
    });
    final settings = AppSettings.defaults().copyWith(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      namedEndpoints: [meshEndpoint],
      subagentModel: 'mesh-subagent',
      subagentEndpointId: meshEndpoint.id,
    );

    await _pumpPage(
      tester,
      client: client,
      settings: settings,
      dataSourceFactory: (endpoint) => ModelRemoteDataSource(
        baseUrl: endpoint.baseUrl,
        apiKey: endpoint.apiKey,
        client: client,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('local-stack-endpoint-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mesh Box').last);
    await tester.pumpAndSettle();

    expect(find.text('mesh-subagent'), findsOneWidget);
    expect(
      find.text('1 of 1 role models need loading on this endpoint.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('local-stack-prepare-role-models')),
    );
    await tester.pumpAndSettle();

    final meshLoadRequests = requests
        .where(
          (request) =>
              request.url.host == 'mesh-box' &&
              request.url.path == '/models/load',
        )
        .toList();
    expect(meshLoadRequests, hasLength(1));
    expect(meshLoadRequests.single.body, '{"model":"mesh-subagent"}');
    expect(
      find.textContaining('Role models prepared: 1 loaded'),
      findsOneWidget,
    );
  });

  testWidgets('shows resource guidance from detected host memory', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/models') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'Qwen3-7B-Q4_K_M',
                'status': {'value': 'unloaded'},
                'metadata': {'n_ctx': 4096},
              },
              {
                'id': 'Huge-70B-Q8_0',
                'status': {'value': 'unloaded'},
                'metadata': {'n_ctx': 8192},
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    await _pumpPage(
      tester,
      client: client,
      hostProfile: const LocalHostResourceProfile.detected(
        totalMemoryBytes: 32 * localHostBytesPerGiB,
        appleSiliconUnifiedMemory: true,
        detectionMethod: 'test',
      ),
    );

    expect(find.text('Resource guidance'), findsOneWidget);
    expect(
      find.textContaining(
        'Host memory: 32 GB unified memory detected via test',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1 fit, 0 close, 1 too large'), findsOneWidget);
    expect(find.textContaining('Fits memory'), findsOneWidget);
    expect(find.textContaining('Exceeds safe memory budget'), findsOneWidget);
  });

  testWidgets('shows local stack speedup guidance', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/models') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'Qwen3-Coder-30B-A3B-Q4_K_M',
                'status': {'value': 'loaded'},
              },
              {
                'id': 'Qwen3-Coder-Draft-1.5B-Q4_K_M',
                'status': {'value': 'unloaded'},
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    await _pumpPage(
      tester,
      client: client,
      settings: AppSettings.defaults().copyWith(
        model: 'Qwen3-Coder-30B-A3B-Q4_K_M',
      ),
    );

    expect(find.text('Speedups'), findsOneWidget);
    expect(find.textContaining('--spec-type ngram-simple'), findsOneWidget);
    expect(
      find.textContaining(
        'consider compatible draft model Qwen3-Coder-Draft-1.5B-Q4_K_M',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows role suggestions for smaller fit role models', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/models') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'Qwen3-Coder-30B-A3B-Q4_K_M',
                'status': {'value': 'loaded'},
              },
              {
                'id': 'Qwen3-1.7B-Q4_K_M',
                'status': {'value': 'unloaded'},
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    await _pumpPage(
      tester,
      client: client,
      settings: AppSettings.defaults().copyWith(
        model: 'Qwen3-Coder-30B-A3B-Q4_K_M',
      ),
      hostProfile: const LocalHostResourceProfile.detected(
        totalMemoryBytes: 64 * localHostBytesPerGiB,
        appleSiliconUnifiedMemory: true,
        detectionMethod: 'test',
      ),
    );

    expect(find.text('Role suggestions'), findsOneWidget);
    expect(
      find.textContaining('Memory extraction falls back to main model'),
      findsOneWidget,
    );
    expect(
      find.textContaining('consider assigning Qwen3-1.7B-Q4_K_M'),
      findsWidgets,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required http.Client client,
  AppSettings? settings,
  LocalModelLifecycleDataSourceFactory? dataSourceFactory,
  LocalHostResourceProfile? hostProfile,
}) async {
  final resolvedSettings =
      settings ??
      AppSettings.defaults().copyWith(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'no-key',
      );
  SharedPreferences.setMockInitialValues({
    'app_settings': jsonEncode(resolvedSettings.toJson()),
  });
  final prefs = await SharedPreferences.getInstance();

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoader(),
      child: Builder(
        builder: (context) {
          return ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              localModelLifecycleDataSourceProvider.overrideWithValue(
                ModelRemoteDataSource(
                  baseUrl: resolvedSettings.baseUrl,
                  apiKey: resolvedSettings.apiKey,
                  client: client,
                ),
              ),
              if (dataSourceFactory != null)
                localModelLifecycleDataSourceFactoryProvider.overrideWithValue(
                  dataSourceFactory,
                ),
              localHostResourceProfileProvider.overrideWith(
                (ref) async =>
                    hostProfile ??
                    const LocalHostResourceProfile.unknown(
                      message: 'Test host profile omitted.',
                    ),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const LocalStackSettingsPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
