import 'dart:async';

import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/chat/domain/services/pending_approval_summary.dart';
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

  testWidgets('a withdrawn approval takes its sheet away', (tester) async {
    // The page opened sheets and never closed them. Answering at the desktop,
    // or withdrawing the per-device grant that let this phone see the approval
    // at all, left the phone still asking about it -- and answering it then was
    // refused, because the desktop no longer had it pending.
    SharedPreferences.setMockInitialValues({});
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
        remoteCodingClientProvider.overrideWith(_ConnectedClient.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          // The connected page renders the composer, and a bare `home:` is not
          // a Material ancestor. In the app this page is a Scaffold's body.
          home: Scaffold(body: RemoteCodingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('uptime'),
      findsWidgets,
      reason: 'the approval sheet has to be open before it can be taken away',
    );

    (container.read(remoteCodingClientProvider.notifier) as _ConnectedClient)
        .withdraw();
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Approve'),
      findsNothing,
      reason: 'a question the desktop is no longer asking must not stay up',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a read-only approval can still be closed', (tester) async {
    // It offers no answer, and the modal is deliberately not dismissible so a
    // stray tap cannot resolve an approval. Without a close button that
    // combination is a trap: the phone waits on the desktop before it can do
    // anything else.
    SharedPreferences.setMockInitialValues({});
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
        remoteCodingClientProvider.overrideWith(_ConnectedClient.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RemoteCodingPage())),
      ),
    );
    await tester.pumpAndSettle();
    (container.read(remoteCodingClientProvider.notifier) as _ConnectedClient)
        .offerStructuredInput();
    await tester.pumpAndSettle();

    expect(
      find.text('SSH connection'),
      findsWidgets,
      reason: 'the structured-input approval has to be on screen',
    );
    expect(
      find.widgetWithText(FilledButton, 'Approve'),
      findsNothing,
      reason: 'a kind the phone cannot finish must offer no answer',
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Credentials are required.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final class _DisconnectedClient extends RemoteCodingClientNotifier {
  @override
  RemoteCodingClientState build() => const RemoteCodingClientState();
}

/// A connected client whose pending approval the test can withdraw.
final class _ConnectedClient extends RemoteCodingClientNotifier {
  static const approval = RemoteCodingApproval(
    id: 'approval-1',
    kind: PendingApprovalKinds.localCommand,
    title: 'uptime',
    subtitle: '/Users/dev/project',
    detail: 'uptime',
    isSimpleDecision: true,
  );

  @override
  RemoteCodingClientState build() => const RemoteCodingClientState(
    status: RemoteCodingConnectionStatus.connected,
    pendingApproval: approval,
  );

  /// What the desktop does when the interaction stops being this device's to
  /// answer: it answers it itself, or the grant that let this device see it is
  /// withdrawn. Either way the next snapshot carries no approval.
  void withdraw() => state = state.copyWith(clearPendingApproval: true);

  /// A kind that needs input no phone can collect, so the sheet carries no
  /// answer at all.
  void offerStructuredInput() => state = state.copyWith(
    pendingApproval: const RemoteCodingApproval(
      id: 'ssh-connect-1',
      kind: PendingApprovalKinds.sshConnect,
      title: 'SSH connection',
      subtitle: 'deploy@build-box',
      detail: 'Credentials are required.',
      isSimpleDecision: false,
    ),
  );
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
