import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/crashlytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterExceptionHandler? previousFlutterOnError;
  late ErrorCallback? previousPlatformOnError;

  setUp(() {
    previousFlutterOnError = FlutterError.onError;
    previousPlatformOnError = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = previousFlutterOnError;
    PlatformDispatcher.instance.onError = previousPlatformOnError;
  });

  test('skips Flutter test hosts without touching the adapter', () async {
    final adapter = _FakeCrashlyticsAdapter();
    final installed = await CrashlyticsService(
      adapter: adapter,
      isFlutterTest: true,
      isDebugMode: false,
    ).install();

    expect(installed, isFalse);
    expect(adapter.ensureInitializedCalls, 0);
    expect(FlutterError.onError, same(previousFlutterOnError));
  });

  test('skips unsupported platforms without initializing Firebase', () async {
    final adapter = _FakeCrashlyticsAdapter(isSupported: false);
    final installed = await CrashlyticsService(
      adapter: adapter,
      isFlutterTest: false,
      isDebugMode: false,
    ).install();

    expect(installed, isFalse);
    expect(adapter.ensureInitializedCalls, 0);
  });

  test('fails closed when Firebase configuration is missing', () async {
    final adapter = _FakeCrashlyticsAdapter(
      initializeError: StateError('missing GoogleService-Info.plist'),
    );
    final previousHandler = FlutterError.onError;
    final installed = await CrashlyticsService(
      adapter: adapter,
      isFlutterTest: false,
      isDebugMode: false,
    ).install();

    expect(installed, isFalse);
    expect(adapter.collectionEnabled, isNull);
    expect(FlutterError.onError, same(previousHandler));
  });

  test('disables collection in debug builds unless opted in', () async {
    final adapter = _FakeCrashlyticsAdapter();
    final installed = await CrashlyticsService(
      adapter: adapter,
      isFlutterTest: false,
      isDebugMode: true,
      debugCollectionEnabled: false,
      customKeys: const {'build_commit': 'abc123'},
    ).install();

    expect(installed, isTrue);
    expect(adapter.collectionEnabled, isFalse);
    expect(adapter.customKeys, isEmpty);
  });

  test('installs fatal handlers and custom keys in release', () async {
    final adapter = _FakeCrashlyticsAdapter();
    final service = CrashlyticsService(
      adapter: adapter,
      isFlutterTest: false,
      isDebugMode: false,
      customKeys: const {'build_commit': 'abc123', 'build_dirty': false},
    );

    expect(await service.install(), isTrue);
    expect(adapter.collectionEnabled, isTrue);
    expect(adapter.customKeys, {
      'build_commit': 'abc123',
      'build_dirty': false,
    });

    final details = FlutterErrorDetails(
      exception: StateError('widget boom'),
      stack: StackTrace.current,
    );
    FlutterError.onError!(details);
    expect(adapter.flutterErrors, [details]);

    final handled = PlatformDispatcher.instance.onError!(
      StateError('async boom'),
      StackTrace.current,
    );
    expect(handled, isTrue);
    expect(adapter.errors, hasLength(1));
    expect(adapter.errors.single.fatal, isTrue);
    expect(adapter.errors.single.error, isA<StateError>());
  });

  test('debug dart-define enables collection for verification', () async {
    final adapter = _FakeCrashlyticsAdapter();
    final installed = await CrashlyticsService(
      adapter: adapter,
      isFlutterTest: false,
      isDebugMode: true,
      debugCollectionEnabled: true,
      customKeys: const {'build_commit': 'debug'},
    ).install();

    expect(installed, isTrue);
    expect(adapter.collectionEnabled, isTrue);
    expect(adapter.customKeys['build_commit'], 'debug');
  });
}

final class _FakeCrashlyticsAdapter implements CrashlyticsPlatformAdapter {
  _FakeCrashlyticsAdapter({this.isSupported = true, this.initializeError});

  @override
  final bool isSupported;

  final Object? initializeError;
  int ensureInitializedCalls = 0;
  bool? collectionEnabled;
  final Map<String, Object> customKeys = {};
  final List<FlutterErrorDetails> flutterErrors = [];
  final List<({Object error, StackTrace stack, bool fatal})> errors = [];

  @override
  Future<void> ensureInitialized() async {
    ensureInitializedCalls += 1;
    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    collectionEnabled = enabled;
  }

  @override
  Future<void> setCustomKeys(Map<String, Object> keys) async {
    customKeys
      ..clear()
      ..addAll(keys);
  }

  @override
  void recordFlutterFatalError(FlutterErrorDetails details) {
    flutterErrors.add(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stack, {
    required bool fatal,
  }) async {
    errors.add((error: error, stack: stack, fatal: fatal));
  }
}
