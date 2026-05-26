import 'dart:io';

import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hashToken stores a digest instead of the raw token', () {
    const token = 'secret-device-token';

    final hash = RemoteCodingSecurity.hashToken(token);

    expect(hash, isNot(token));
    expect(hash, hasLength(64));
    expect(RemoteCodingSecurity.hashToken(token), hash);
  });

  test('constantTimeEquals matches only identical strings', () {
    expect(RemoteCodingSecurity.constantTimeEquals('abc', 'abc'), isTrue);
    expect(RemoteCodingSecurity.constantTimeEquals('abc', 'abd'), isFalse);
    expect(RemoteCodingSecurity.constantTimeEquals('abc', 'abcd'), isFalse);
  });

  test('LAN policy allows private and loopback addresses only', () {
    expect(
      RemoteCodingNetworkPolicy.isLanAddress(InternetAddress('127.0.0.1')),
      isTrue,
    );
    expect(
      RemoteCodingNetworkPolicy.isLanAddress(InternetAddress('192.168.1.24')),
      isTrue,
    );
    expect(
      RemoteCodingNetworkPolicy.isLanAddress(InternetAddress('172.20.1.24')),
      isTrue,
    );
    expect(
      RemoteCodingNetworkPolicy.isLanAddress(InternetAddress('10.0.0.5')),
      isTrue,
    );
    expect(
      RemoteCodingNetworkPolicy.isLanAddress(InternetAddress('8.8.8.8')),
      isFalse,
    );
  });

  test('LAN host policy accepts only local address literals', () {
    expect(RemoteCodingNetworkPolicy.isLanHost('localhost'), isTrue);
    expect(RemoteCodingNetworkPolicy.isLanHost('192.168.1.24'), isTrue);
    expect(RemoteCodingNetworkPolicy.isLanHost('10.0.0.5'), isTrue);
    expect(RemoteCodingNetworkPolicy.isLanHost('8.8.8.8'), isFalse);
    expect(RemoteCodingNetworkPolicy.isLanHost('example.com'), isFalse);
  });
}
