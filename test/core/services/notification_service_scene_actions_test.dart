import 'dart:convert';

import 'package:caverno/core/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the contract between `NotificationService` and the
/// `NotificationActionPlugin` half in `ios/Runner/AppDelegate.swift`.
///
/// The channel name and the argument keys are hand-matched across two
/// languages with nothing else holding them together, and this app adopts
/// UIScene, so this channel is the *only* way an Approve or Deny reaches Dart.
/// Renaming either side alone would silence every wrist and lock-screen
/// approval with the rest of the suite green.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(NotificationService.sceneActionChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late NotificationService service;
  late List<Map<String, String>> pending;

  Future<void> deliver(List<Map<String, String>> actions) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('notificationActions', actions),
      ),
      (_) {},
    );
  }

  String approvalPayload(String approvalId) => jsonEncode({
    'kind': 'approval_required',
    'conversationId': 'conversation-1',
    'approvalId': approvalId,
  });

  setUp(() {
    // `FlutterLocalNotificationsPlugin.initialize` resolves the platform
    // instance, which no test host registers.
    FlutterLocalNotificationsPlatform.instance = _StubPlatform();
    pending = [];
    // Stands in for the Swift side, which answers the drain that
    // `init()` performs once its handler is installed.
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takePendingActions') return pending;
      return null;
    });
    service = NotificationService();
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      service.dispose();
    });
  });

  test('the channel name matches the one the Swift side publishes', () {
    expect(
      NotificationService.sceneActionChannelName,
      'com.caverno/notification_actions',
    );
  });

  test('an approve action reaches the action stream', () async {
    await service.init();
    final actions = service.notificationActions.take(1).toList();

    await deliver([
      {
        'actionId': NotificationService.approveActionId,
        'payload': approvalPayload('approval-1'),
      },
    ]);

    final received = (await actions).single;
    expect(received.isApprove, isTrue);
    expect(received.approvalId, 'approval-1');
  });

  test('a deny action reaches the action stream', () async {
    await service.init();
    final actions = service.notificationActions.take(1).toList();

    await deliver([
      {
        'actionId': NotificationService.denyActionId,
        'payload': approvalPayload('approval-2'),
      },
    ]);

    final received = (await actions).single;
    expect(received.isDeny, isTrue);
  });

  test('presses that arrived before Dart attached are drained', () async {
    // A background launch delivers the press to the native side long before an
    // isolate exists, so pushing it then would send it nowhere. Dart pulls.
    pending = [
      {
        'actionId': NotificationService.approveActionId,
        'payload': approvalPayload('approval-early'),
      },
    ];
    final actions = service.notificationActions.take(1).toList();

    await service.init();

    expect((await actions).single.approvalId, 'approval-early');
  });

  test('every queued press is delivered, not just the last', () async {
    // Two threads can block at once; a single-slot buffer dropped the first.
    final actions = service.notificationActions.take(2).toList();
    await service.init();

    await deliver([
      {
        'actionId': NotificationService.approveActionId,
        'payload': approvalPayload('approval-a'),
      },
      {
        'actionId': NotificationService.denyActionId,
        'payload': approvalPayload('approval-b'),
      },
    ]);

    expect(
      (await actions).map((action) => action.approvalId),
      ['approval-a', 'approval-b'],
    );
  });

  test('a non-approval action is routed as a tap, not a decision', () async {
    await service.init();
    final taps = service.notificationTapPayloads.take(1).toList();

    await deliver([
      {'actionId': 'open', 'payload': approvalPayload('approval-3')},
    ]);

    expect((await taps).single, contains('approval-3'));
  });

  test('disposing releases the handler so a later service can take it', () async {
    await service.init();
    service.dispose();

    final replacement = NotificationService();
    addTearDown(replacement.dispose);
    await replacement.init();
    final actions = replacement.notificationActions.take(1).toList();

    await deliver([
      {
        'actionId': NotificationService.approveActionId,
        'payload': approvalPayload('approval-4'),
      },
    ]);

    expect((await actions).single.approvalId, 'approval-4');
  });
}


/// The plugin resolves this during `initialize`; nothing here is exercised.
final class _StubPlatform extends FlutterLocalNotificationsPlatform {}
