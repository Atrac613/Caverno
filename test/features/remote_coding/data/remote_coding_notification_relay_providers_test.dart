import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relay client is absent when no fixed HTTPS origin is configured', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(remoteCodingNotificationRelayClientProvider), isNull);
  });

  test('relay client rejects an insecure configured origin', () {
    final container = ProviderContainer(
      overrides: [
        remoteCodingNotificationRelayOriginProvider.overrideWithValue(
          'http://relay.example.test',
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(remoteCodingNotificationRelayClientProvider), isNull);
  });
}
