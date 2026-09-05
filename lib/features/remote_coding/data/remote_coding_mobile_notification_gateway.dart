import 'dart:async';
import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'remote_coding_notification_relay_contract.dart';

enum RemoteCodingNotificationPermission {
  notDetermined,
  denied,
  authorized,
  provisional,
}

abstract interface class RemoteCodingMobileNotificationGateway {
  RemoteCodingRelayPlatform? get platform;

  Future<RemoteCodingNotificationPermission> initialize();


  Future<RemoteCodingNotificationPermission> requestPermission();

  Future<String> getFcmToken();

  Future<void> disableFcmToken();

  Future<String> getAppCheckToken();

  Stream<String> get onTokenRefresh;

  Stream<Map<String, dynamic>> get onForegroundMessage;

  Stream<Map<String, dynamic>> get onNotificationTap;

  Future<Map<String, dynamic>?> getInitialNotificationTap();
}

final class FirebaseRemoteCodingMobileNotificationGateway
    implements RemoteCodingMobileNotificationGateway {
  FirebaseRemoteCodingMobileNotificationGateway({
    FirebaseMessaging? messaging,
    FirebaseAppCheck? appCheck,
  }) : _messaging = messaging,
       _appCheck = appCheck;

  static const bool _useDebugAppCheck = bool.fromEnvironment(
    'CAVERNO_FIREBASE_APP_CHECK_DEBUG',
  );

  FirebaseMessaging? _messaging;
  FirebaseAppCheck? _appCheck;
  Future<void>? _initialization;

  @override
  RemoteCodingRelayPlatform? get platform {
    if (kIsWeb) {
      return null;
    }
    if (Platform.isIOS) {
      return RemoteCodingRelayPlatform.ios;
    }
    if (Platform.isAndroid) {
      return RemoteCodingRelayPlatform.android;
    }
    return null;
  }

  @override
  Future<RemoteCodingNotificationPermission> initialize() async {
    if (platform == null) {
      throw UnsupportedError(
        'Remote coding push notifications require iOS or Android.',
      );
    }
    _initialization ??= _initializeFirebase();
    await _initialization;
    final settings = await _requireMessaging().getNotificationSettings();
    return _mapAuthorizationStatus(settings.authorizationStatus);
  }

  Future<void> _initializeFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    _appCheck ??= FirebaseAppCheck.instance;
    await _appCheck!.activate(
      providerAndroid: _useDebugAppCheck
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: _useDebugAppCheck
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
    _messaging ??= FirebaseMessaging.instance;
  }

  @override
  Future<RemoteCodingNotificationPermission> requestPermission() async {
    await initialize();
    final settings = await _requireMessaging().requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return _mapAuthorizationStatus(settings.authorizationStatus);
  }

  @override
  Future<String> getFcmToken() async {
    await initialize();
    await _requireMessaging().setAutoInitEnabled(true);
    if (platform == RemoteCodingRelayPlatform.ios) {
      await _waitForApnsToken();
    }
    final token = (await _requireMessaging().getToken())?.trim();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase did not return an FCM registration token.');
    }
    return token;
  }

  @override
  Future<void> disableFcmToken() async {
    await initialize();
    await _requireMessaging().deleteToken();
    await _requireMessaging().setAutoInitEnabled(false);
  }

  Future<void> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 20; attempt += 1) {
      final token = (await _requireMessaging().getAPNSToken())?.trim();
      if (token != null && token.isNotEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('APNs registration is not ready.');
  }

  @override
  Future<String> getAppCheckToken() async {
    await initialize();
    final token = (await _requireAppCheck().getLimitedUseToken()).trim();
    if (token.isEmpty) {
      throw StateError('Firebase did not return an App Check token.');
    }
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => _requireMessaging().onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onForegroundMessage => FirebaseMessaging
      .onMessage
      .map((message) => Map<String, dynamic>.from(message.data));

  @override
  Stream<Map<String, dynamic>> get onNotificationTap => FirebaseMessaging
      .onMessageOpenedApp
      .map((message) => Map<String, dynamic>.from(message.data));

  @override
  Future<Map<String, dynamic>?> getInitialNotificationTap() async {
    await initialize();
    final message = await _requireMessaging().getInitialMessage();
    return message == null ? null : Map<String, dynamic>.from(message.data);
  }

  FirebaseMessaging _requireMessaging() {
    final messaging = _messaging;
    if (messaging == null) {
      throw StateError('Firebase Messaging is not initialized.');
    }
    return messaging;
  }

  FirebaseAppCheck _requireAppCheck() {
    final appCheck = _appCheck;
    if (appCheck == null) {
      throw StateError('Firebase App Check is not initialized.');
    }
    return appCheck;
  }
}

RemoteCodingNotificationPermission _mapAuthorizationStatus(
  AuthorizationStatus status,
) {
  return switch (status) {
    AuthorizationStatus.authorized =>
      RemoteCodingNotificationPermission.authorized,
    // firebase_messaging 16.6.0 split out the state where the platform will no
    // longer surface a permission prompt. The remedy is identical to a plain
    // denial here -- the user has to re-enable notifications in system
    // settings -- and that is exactly what the denied copy already says.
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently =>
      RemoteCodingNotificationPermission.denied,
    AuthorizationStatus.notDetermined =>
      RemoteCodingNotificationPermission.notDetermined,
    AuthorizationStatus.provisional =>
      RemoteCodingNotificationPermission.provisional,
  };
}
