import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/providers/settings_notifier.dart';
import 'remote_coding_mobile_notification_gateway.dart';
import 'remote_coding_notification_receipt_store.dart';
import 'remote_coding_notification_relay_client.dart';

const _configuredNotificationRelayOrigin = String.fromEnvironment(
  'CAVERNO_NOTIFICATION_RELAY_URL',
);

final remoteCodingNotificationRelayOriginProvider = Provider<String>(
  (ref) => _configuredNotificationRelayOrigin,
);

final remoteCodingNotificationRelayClientProvider =
    Provider<RemoteCodingNotificationRelayClient?>((ref) {
      final configuredOrigin = ref.watch(
        remoteCodingNotificationRelayOriginProvider,
      );
      if (configuredOrigin.trim().isEmpty) {
        return null;
      }
      try {
        return HttpRemoteCodingNotificationRelayClient(
          endpoint: RemoteCodingNotificationRelayEndpoint.parse(
            configuredOrigin,
          ),
        );
      } on FormatException {
        return null;
      }
    });

final remoteCodingMobileNotificationGatewayProvider =
    Provider<RemoteCodingMobileNotificationGateway>(
      (ref) => FirebaseRemoteCodingMobileNotificationGateway(),
    );

final remoteCodingNotificationReceiptStoreProvider =
    Provider<RemoteCodingNotificationReceiptStore>(
      (ref) => RemoteCodingNotificationReceiptStore(
        ref.watch(sharedPreferencesProvider),
      ),
    );
