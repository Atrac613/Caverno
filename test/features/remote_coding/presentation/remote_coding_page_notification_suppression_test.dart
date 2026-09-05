import 'dart:async';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_mobile_notification_gateway.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_providers.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_receipt_store.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_secure_store.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_mobile_notification_notifier.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_page.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The page tells the notifier when it is on screen so an approval sheet and
/// an approval notification do not ask the same question twice.
///
/// Leaving the page has to clear that, and the first implementation could not:
/// it read `ref` inside `dispose`, which throws a `StateError`. The flag stayed
/// set for the rest of the session, every later approval was suppressed on
/// every screen, and `dispose` aborted before releasing the page's controllers.
/// A stuck suppression flag silences the whole feature, so this is the failure
/// mode worth a test of its own.
void main() {
  setUp(() {
    debugRemoteCodingMobileRuntimePlatformOverride = () => true;
  });

  tearDown(() {
    debugRemoteCodingMobileRuntimePlatformOverride = null;
  });

  testWidgets('leaving the page clears notification suppression', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        remoteCodingRepositoryProvider.overrideWithValue(
          RemoteCodingRepository(preferences, secureStore: _NoSecureStore()),
        ),
        remoteCodingMobileNotificationGatewayProvider.overrideWithValue(
          _UnsupportedGateway(),
        ),
        remoteCodingNotificationRelayClientProvider.overrideWithValue(null),
        remoteCodingNotificationReceiptStoreProvider.overrideWithValue(
          RemoteCodingNotificationReceiptStore(preferences),
        ),
        notificationServiceProvider.overrideWithValue(_SilentNotifications()),
        remoteCodingClientProvider.overrideWith(_DisconnectedClient.new),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(
      remoteCodingMobileNotificationProvider.notifier,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RemoteCodingPage()),
      ),
    );
    expect(notifier.debugIsRemoteCodingPageMounted, isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      notifier.debugIsRemoteCodingPageMounted,
      isFalse,
      reason:
          'a suppression flag that cannot be cleared silences every later '
          'approval on every screen',
    );
    expect(tester.takeException(), isNull);
  });
}

final class _DisconnectedClient extends RemoteCodingClientNotifier {
  @override
  RemoteCodingClientState build() => const RemoteCodingClientState();
}

final class _SilentNotifications extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<String?> getInitialNotificationTapPayload() async => null;

  @override
  Stream<String> get notificationTapPayloads => const Stream<String>.empty();
}

final class _UnsupportedGateway
    implements RemoteCodingMobileNotificationGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  RemoteCodingRelayPlatform? get platform => null;
}

final class _NoSecureStore implements RemoteCodingSecureStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
