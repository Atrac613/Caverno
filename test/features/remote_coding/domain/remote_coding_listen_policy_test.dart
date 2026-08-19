import 'dart:io';

import 'package:caverno/features/remote_coding/domain/remote_coding_listen_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug policy allows a plaintext LAN bind address', () {
    final address = const RemoteCodingListenPolicy(
      isRelease: false,
    ).bindAddress(requested: InternetAddress.anyIPv4);

    expect(address, InternetAddress.anyIPv4);
    expect(address.isLoopback, isFalse);
  });

  test('release policy refuses a plaintext non-loopback bind address', () {
    expect(
      () => const RemoteCodingListenPolicy(
        isRelease: true,
      ).bindAddress(requested: InternetAddress.anyIPv4),
      throwsA(isA<RemoteCodingPlaintextLanForbiddenException>()),
    );
    expect(
      () => const RemoteCodingListenPolicy(
        isRelease: true,
      ).bindAddress(requested: InternetAddress('192.168.1.24')),
      throwsA(isA<RemoteCodingPlaintextLanForbiddenException>()),
    );
  });

  test('release policy allows an explicit loopback bind', () {
    final address = const RemoteCodingListenPolicy(
      isRelease: true,
    ).bindAddress(requested: InternetAddress.loopbackIPv4);

    expect(address.isLoopback, isTrue);
  });

  test('current policy uses the product compile flag', () {
    final source = File(
      'lib/features/remote_coding/domain/remote_coding_listen_policy.dart',
    ).readAsStringSync();
    final notifier = File(
      'lib/features/remote_coding/presentation/remote_coding_server_notifier.dart',
    ).readAsStringSync();

    expect(source, contains("bool.fromEnvironment('dart.vm.product')"));
    expect(notifier, contains('RemoteCodingListenPolicy.current()'));
    expect(
      notifier,
      isNot(contains('HttpServer.bind(InternetAddress.anyIPv4')),
    );
  });
}
