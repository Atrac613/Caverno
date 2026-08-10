import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_notification_receipt_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('claims each event only once across store instances', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.utc(2026, 8, 10, 12);

    expect(
      await RemoteCodingNotificationReceiptStore(
        preferences,
      ).claim('event_123', now),
      isTrue,
    );
    expect(
      await RemoteCodingNotificationReceiptStore(
        preferences,
      ).claim('event_123', now.add(const Duration(minutes: 1))),
      isFalse,
    );
  });

  test('prunes expired receipts and keeps the configured bound', () async {
    final now = DateTime.utc(2026, 8, 10, 12);
    SharedPreferences.setMockInitialValues({
      'remote_coding_terminal_notification_receipts': jsonEncode({
        'expired_event': now
            .subtract(const Duration(days: 8))
            .toIso8601String(),
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final store = RemoteCodingNotificationReceiptStore(
      preferences,
      maximumReceipts: 2,
    );

    expect(await store.claim('event_1', now), isTrue);
    expect(
      await store.claim('event_2', now.add(const Duration(seconds: 1))),
      isTrue,
    );
    expect(
      await store.claim('event_3', now.add(const Duration(seconds: 2))),
      isTrue,
    );

    final saved =
        jsonDecode(
              preferences.getString(
                'remote_coding_terminal_notification_receipts',
              )!,
            )
            as Map<String, dynamic>;
    expect(saved.keys, containsAll(<String>['event_2', 'event_3']));
    expect(saved, hasLength(2));
  });

  test('rejects event IDs outside the opaque identifier boundary', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RemoteCodingNotificationReceiptStore(
      await SharedPreferences.getInstance(),
    );

    expect(
      () => store.claim('event with spaces', DateTime.now()),
      throwsA(isA<FormatException>()),
    );
  });
}
