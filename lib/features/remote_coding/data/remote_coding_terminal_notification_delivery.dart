import 'dart:async';

import '../../../core/utils/logger.dart';
import '../domain/remote_coding_models.dart';
import 'remote_coding_notification_payload.dart';
import 'remote_coding_notification_relay_client.dart';
import 'remote_coding_notification_relay_contract.dart';
import 'remote_coding_repository.dart';

typedef RemoteCodingNotificationRetryDelay =
    Future<void> Function(Duration duration);

final class RemoteCodingTerminalNotificationDeliveryReport {
  const RemoteCodingTerminalNotificationDeliveryReport({
    required this.configuredDeviceCount,
    required this.attemptedDeviceCount,
    required this.deliveredDeviceCount,
    required this.failedDeviceCount,
    required this.completedAt,
  });

  final int configuredDeviceCount;
  final int attemptedDeviceCount;
  final int deliveredDeviceCount;
  final int failedDeviceCount;
  final DateTime completedAt;

  Map<String, dynamic> toDiagnosticsJson() => <String, dynamic>{
    'configuredDeviceCount': configuredDeviceCount,
    'attemptedDeviceCount': attemptedDeviceCount,
    'deliveredDeviceCount': deliveredDeviceCount,
    'failedDeviceCount': failedDeviceCount,
    'completedAt': completedAt.toUtc().toIso8601String(),
  };
}

final class RemoteCodingTerminalNotificationDeliveryService {
  RemoteCodingTerminalNotificationDeliveryService({
    required this.repository,
    required this.relayClient,
    required this.clock,
    RemoteCodingNotificationRetryDelay? retryDelay,
  }) : retryDelay = retryDelay ?? Future<void>.delayed;

  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 250),
    Duration(seconds: 1),
  ];

  final RemoteCodingRepository repository;
  final RemoteCodingNotificationRelayClient relayClient;
  final RemoteCodingRelayClock clock;
  final RemoteCodingNotificationRetryDelay retryDelay;

  Future<RemoteCodingTerminalNotificationDeliveryReport> deliver({
    required RemoteCodingNotificationPayload notification,
    required List<RemoteCodingPairedDevice> devices,
  }) async {
    final now = clock().toUtc();
    final configured = devices
        .where((device) => device.hasNotificationRelay)
        .toList(growable: false);
    final eligible = configured
        .where((device) => device.hasUsableNotificationRelayAt(now))
        .toList(growable: false);
    final results = await Future.wait<bool>(
      eligible.map(
        (device) =>
            _deliverToDevice(device: device, notification: notification),
      ),
    );
    final deliveredCount = results.where((delivered) => delivered).length;
    return RemoteCodingTerminalNotificationDeliveryReport(
      configuredDeviceCount: configured.length,
      attemptedDeviceCount: eligible.length,
      deliveredDeviceCount: deliveredCount,
      failedDeviceCount: eligible.length - deliveredCount,
      completedAt: clock().toUtc(),
    );
  }

  Future<bool> _deliverToDevice({
    required RemoteCodingPairedDevice device,
    required RemoteCodingNotificationPayload notification,
  }) async {
    final deliveryHandle = device.relayDeliveryHandle;
    final deliveryKeyId = device.relayDeliveryKeyId;
    String? deliverySecret;
    try {
      deliverySecret = await repository.loadDesktopRelayDeliverySecret(
        device.id,
      );
    } catch (error) {
      appLog(
        '[RemoteCodingRelay] reading a delivery credential failed: $error',
      );
      return false;
    }
    if (deliveryHandle == null ||
        deliveryKeyId == null ||
        deliverySecret == null ||
        deliverySecret.trim().isEmpty) {
      return false;
    }
    for (var attempt = 0; attempt <= _retryDelays.length; attempt += 1) {
      try {
        await relayClient.deliver(
          deliveryHandle: deliveryHandle,
          deliveryKeyId: deliveryKeyId,
          deliverySecret: deliverySecret,
          request: RemoteCodingRelayDeliveryRequest(notification: notification),
        );
        return true;
      } on RemoteCodingRelayClientException catch (error) {
        if (error.statusCode == 409) {
          return true;
        }
        if (!_isRetryable(error) || attempt == _retryDelays.length) {
          return false;
        }
        await retryDelay(_retryDelays[attempt]);
      } catch (error) {
        appLog('[RemoteCodingRelay] delivery attempt failed: $error');
        return false;
      }
    }
    return false;
  }
}

bool _isRetryable(RemoteCodingRelayClientException error) {
  if (error.failure == RemoteCodingRelayClientFailure.transport) {
    return true;
  }
  final statusCode = error.statusCode;
  return statusCode == 429 ||
      (statusCode != null && statusCode >= 500 && statusCode < 600);
}
