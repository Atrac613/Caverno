import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../constants/build_info.dart';
import '../utils/logger.dart';

/// Enable Crashlytics collection in debug builds.
///
/// Release and profile already collect when Firebase app configuration is
/// present. Debug stays off unless this flag is set, so local development
/// does not upload stack traces by default.
const bool kCavernoCrashlyticsDebugCollection = bool.fromEnvironment(
  'CAVERNO_CRASHLYTICS_DEBUG',
);

/// Installs Crashlytics for the GUI app after Flutter bindings exist.
///
/// Missing Firebase configuration, unsupported platforms, and test hosts fail
/// closed without blocking startup. The CLI frontend never calls this.
Future<bool> installCavernoCrashlytics({CrashlyticsService? service}) {
  return (service ?? CrashlyticsService()).install();
}

/// Platform calls used by [CrashlyticsService]. Production uses
/// [FirebaseCrashlyticsAdapter]; tests inject a fake.
abstract interface class CrashlyticsPlatformAdapter {
  bool get isSupported;

  Future<void> ensureInitialized();

  Future<void> setCollectionEnabled(bool enabled);

  Future<void> setCustomKeys(Map<String, Object> keys);

  void recordFlutterFatalError(FlutterErrorDetails details);

  Future<void> recordError(
    Object error,
    StackTrace stack, {
    required bool fatal,
  });
}

/// Firebase-backed Crashlytics adapter for iOS, Android, and macOS.
final class FirebaseCrashlyticsAdapter implements CrashlyticsPlatformAdapter {
  const FirebaseCrashlyticsAdapter();

  @override
  bool get isSupported {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  Future<void> ensureInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) {
    return FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      enabled,
    );
  }

  @override
  Future<void> setCustomKeys(Map<String, Object> keys) async {
    final crashlytics = FirebaseCrashlytics.instance;
    for (final entry in keys.entries) {
      await crashlytics.setCustomKey(entry.key, entry.value);
    }
  }

  @override
  void recordFlutterFatalError(FlutterErrorDetails details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stack, {
    required bool fatal,
  }) {
    return FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
  }
}

/// Hooks Flutter and platform error handlers into Crashlytics.
///
/// Collection is enabled only in profile/release, or in debug when
/// [kCavernoCrashlyticsDebugCollection] is true. Builds without Firebase app
/// files keep running with Crashlytics disabled.
final class CrashlyticsService {
  CrashlyticsService({
    CrashlyticsPlatformAdapter? adapter,
    bool? isFlutterTest,
    bool? isDebugMode,
    bool? debugCollectionEnabled,
    Map<String, Object>? customKeys,
  }) : _adapter = adapter ?? const FirebaseCrashlyticsAdapter(),
       _isFlutterTest =
           isFlutterTest ?? Platform.environment.containsKey('FLUTTER_TEST'),
       _isDebugMode = isDebugMode ?? kDebugMode,
       _debugCollectionEnabled =
           debugCollectionEnabled ?? kCavernoCrashlyticsDebugCollection,
       _customKeys =
           customKeys ??
           {'build_commit': BuildInfo.commit, 'build_dirty': BuildInfo.dirty};

  final CrashlyticsPlatformAdapter _adapter;
  final bool _isFlutterTest;
  final bool _isDebugMode;
  final bool _debugCollectionEnabled;
  final Map<String, Object> _customKeys;

  /// Whether uncaught errors should be uploaded after a successful [install].
  bool get collectionEnabled => !_isDebugMode || _debugCollectionEnabled;

  Future<bool> install() async {
    if (_isFlutterTest || !_adapter.isSupported) {
      return false;
    }

    try {
      await _adapter.ensureInitialized();
      await _adapter.setCollectionEnabled(collectionEnabled);
      if (collectionEnabled && _customKeys.isNotEmpty) {
        await _adapter.setCustomKeys(_customKeys);
      }
      FlutterError.onError = _adapter.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        _adapter.recordError(error, stack, fatal: true);
        return true;
      };
      return true;
    } catch (error, stackTrace) {
      appLog('[Crashlytics] unavailable; continuing without crash reports');
      appLog('[Crashlytics] $error');
      appLog('[Crashlytics] $stackTrace');
      return false;
    }
  }
}
