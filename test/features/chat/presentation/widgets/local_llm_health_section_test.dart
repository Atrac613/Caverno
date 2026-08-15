import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/widgets/local_llm_health_section.dart';
import 'package:caverno/features/settings/domain/entities/local_llm_health.dart';
import 'package:caverno/features/settings/presentation/providers/local_llm_health_provider.dart';
import 'package:caverno/features/settings/presentation/providers/local_model_lifecycle_provider.dart';

/// Reads the shipped translation files directly, so the strings under test are
/// the ones the app renders rather than a fixture that can drift from them.
class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  const online = LocalModelLifecycleEndpointConfig(
    id: 'studio',
    baseUrl: 'http://192.168.0.10:1234/v1',
    apiKey: '',
    label: 'Studio Box',
    isPrimary: true,
  );
  const down = LocalModelLifecycleEndpointConfig(
    id: 'spare',
    baseUrl: 'http://192.168.0.11:1234/v1',
    apiKey: '',
    label: 'Spare Box',
    isPrimary: false,
  );

  Future<void> pump(
    WidgetTester tester, {
    required List<LocalModelLifecycleEndpointConfig> endpoints,
    required Map<String, LocalLlmHealthSnapshot> snapshots,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLlmHealthEndpointsProvider.overrideWithValue(endpoints),
          for (final endpoint in endpoints)
            localLlmHealthProvider(
              endpoint,
            ).overrideWith((ref) async => snapshots[endpoint.id]!),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          useOnlyLangCode: true,
          saveLocale: false,
          assetLoader: const _TestTranslationLoader(),
          child: Builder(
            builder: (context) {
              return MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const Scaffold(body: LocalLlmHealthSection()),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows each endpoint with its loaded models', (tester) async {
    await pump(
      tester,
      endpoints: const [online, down],
      snapshots: {
        'studio': LocalLlmHealthSnapshot(
          endpointId: 'studio',
          label: 'Studio Box',
          baseUrl: online.baseUrl,
          isPrimary: true,
          reachability: LocalLlmReachability.online,
          modelEvidence: LocalLlmModelEvidence.loaded,
          modelIds: const ['qwen3.6-27b-vision'],
          checkedAt: DateTime.utc(2026, 8, 15),
        ),
        'spare': LocalLlmHealthSnapshot.offline(
          endpointId: 'spare',
          label: 'Spare Box',
          baseUrl: down.baseUrl,
          isPrimary: false,
          checkedAt: DateTime.utc(2026, 8, 15),
          detail: 'Connection refused',
        ),
      },
    );

    expect(find.text('Studio Box'), findsOneWidget);
    expect(find.text('qwen3.6-27b-vision'), findsOneWidget);
    expect(find.text(online.baseUrl), findsOneWidget);
    expect(find.text('Spare Box'), findsOneWidget);
    expect(find.textContaining('Connection refused'), findsOneWidget);
  });

  testWidgets('marks advertised models as the weaker claim', (tester) async {
    await pump(
      tester,
      endpoints: const [online],
      snapshots: {
        'studio': LocalLlmHealthSnapshot(
          endpointId: 'studio',
          label: 'Studio Box',
          baseUrl: online.baseUrl,
          isPrimary: true,
          reachability: LocalLlmReachability.online,
          modelEvidence: LocalLlmModelEvidence.advertised,
          modelIds: const ['gemma-4-31b'],
          checkedAt: DateTime.utc(2026, 8, 15),
        ),
      },
    );

    expect(find.text('gemma-4-31b'), findsOneWidget);
    expect(find.textContaining('no lifecycle API'), findsOneWidget);
    expect(find.textContaining('Loaded models'), findsNothing);
  });

  testWidgets('says so when no local endpoint is registered', (tester) async {
    await pump(tester, endpoints: const [], snapshots: const {});

    expect(find.textContaining('No local endpoint'), findsOneWidget);
  });
}
