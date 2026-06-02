import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final macosUpdateServiceProvider = Provider<MacosUpdateService>((ref) {
  return const MacosUpdateService();
});

class MacosUpdateService {
  const MacosUpdateService({MethodChannel channel = _defaultChannel})
    : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.caverno/sparkle_updates',
  );

  final MethodChannel _channel;

  bool get isAvailable => Platform.isMacOS;

  Future<MacosUpdateStatus> getStatus() async {
    if (!isAvailable) {
      return const MacosUpdateStatus(
        available: false,
        configured: false,
        feedUrl: '',
        publicKeyConfigured: false,
        automaticallyChecksForUpdates: false,
        automaticallyDownloadsUpdates: false,
        scheduledCheckIntervalSeconds: 3600,
        updateCheckIntervalSeconds: 3600,
        bundleVersion: '',
        bundleShortVersion: '',
        nextAction: 'Sparkle updates are only available on macOS.',
      );
    }

    final response = await _channel.invokeMapMethod<String, Object?>(
      'getStatus',
    );
    return MacosUpdateStatus.fromMap(response ?? const <String, Object?>{});
  }

  Future<MacosUpdateStatus> checkForUpdates() async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'checkForUpdates',
    );
    return MacosUpdateStatus.fromMap(response ?? const <String, Object?>{});
  }
}

class MacosUpdateStatus {
  const MacosUpdateStatus({
    required this.available,
    required this.configured,
    required this.feedUrl,
    required this.publicKeyConfigured,
    required this.automaticallyChecksForUpdates,
    required this.automaticallyDownloadsUpdates,
    required this.scheduledCheckIntervalSeconds,
    required this.updateCheckIntervalSeconds,
    required this.bundleVersion,
    required this.bundleShortVersion,
    this.nextAction,
  });

  factory MacosUpdateStatus.fromMap(Map<String, Object?> map) {
    return MacosUpdateStatus(
      available: _boolValue(map['available']),
      configured: _boolValue(map['configured']),
      feedUrl: map['feedURL']?.toString() ?? '',
      publicKeyConfigured: _boolValue(map['publicKeyConfigured']),
      automaticallyChecksForUpdates: _boolValue(
        map['automaticallyChecksForUpdates'],
      ),
      automaticallyDownloadsUpdates: _boolValue(
        map['automaticallyDownloadsUpdates'],
      ),
      scheduledCheckIntervalSeconds: _numberValue(
        map['scheduledCheckIntervalSeconds'],
        fallback: 3600,
      ),
      updateCheckIntervalSeconds: _numberValue(
        map['updateCheckIntervalSeconds'],
        fallback: 3600,
      ),
      bundleVersion: map['bundleVersion']?.toString() ?? '',
      bundleShortVersion: map['bundleShortVersion']?.toString() ?? '',
      nextAction: map['nextAction']?.toString(),
    );
  }

  final bool available;
  final bool configured;
  final String feedUrl;
  final bool publicKeyConfigured;
  final bool automaticallyChecksForUpdates;
  final bool automaticallyDownloadsUpdates;
  final double scheduledCheckIntervalSeconds;
  final double updateCheckIntervalSeconds;
  final String bundleVersion;
  final String bundleShortVersion;
  final String? nextAction;

  String get displayVersion {
    if (bundleShortVersion.isEmpty && bundleVersion.isEmpty) {
      return '';
    }
    if (bundleShortVersion.isEmpty) {
      return bundleVersion;
    }
    if (bundleVersion.isEmpty) {
      return bundleShortVersion;
    }
    return '$bundleShortVersion+$bundleVersion';
  }

  static bool _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return false;
  }

  static double _numberValue(Object? value, {required double fallback}) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }
}
