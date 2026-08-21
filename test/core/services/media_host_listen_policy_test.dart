import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/media_host_listen_policy.dart';

NetworkInterface _interface(String name, List<String> addresses) => _FakeInterface(
  name,
  addresses
      .map((address) => _FakeInterfaceAddress(InternetAddress(address)))
      .toList(),
);

class _FakeInterface implements NetworkInterface {
  _FakeInterface(this.name, this.addresses);

  @override
  final String name;
  @override
  final List<InterfaceAddress> addresses;
  @override
  int get index => 0;
}

/// `NetworkInterface` hands out [InterfaceAddress], so a plain
/// [InternetAddress] cannot stand in. Everything the policy reads is delegated.
class _FakeInterfaceAddress implements InterfaceAddress {
  _FakeInterfaceAddress(this._delegate);

  final InternetAddress _delegate;

  @override
  String get address => _delegate.address;
  @override
  String get host => _delegate.host;
  @override
  bool get isLinkLocal => _delegate.isLinkLocal;
  @override
  bool get isLoopback => _delegate.isLoopback;
  @override
  bool get isMulticast => _delegate.isMulticast;
  @override
  Uint8List get rawAddress => _delegate.rawAddress;
  @override
  InternetAddressType get type => _delegate.type;
  @override
  Future<InternetAddress> reverse() => _delegate.reverse();
  @override
  int get prefixLength => 24;
  @override
  InternetAddress? get broadcast => null;
}

void main() {
  test('serves loopback when the endpoint is on this machine', () async {
    const policy = MediaHostListenPolicy();

    final binding = await policy.resolve(
      endpoint: Uri.parse('http://127.0.0.1:1234/v1'),
    );

    expect(binding!.bindAddress, InternetAddress.loopbackIPv4);
    expect(binding.advertiseHost, '127.0.0.1');
    expect(binding.isLoopbackOnly, isTrue);
  });

  test('treats localhost by name as this machine', () async {
    const policy = MediaHostListenPolicy();

    final binding = await policy.resolve(
      endpoint: Uri.parse('http://localhost:1234/v1'),
    );

    expect(binding!.isLoopbackOnly, isTrue);
  });

  test('advertises a LAN address for an off-box endpoint', () async {
    final policy = MediaHostListenPolicy(
      interfaces: () => [
        _interface('en0', ['192.168.100.50']),
      ],
    );

    final binding = await policy.resolve(
      endpoint: Uri.parse('http://192.168.100.241:8080/v1'),
    );

    expect(binding!.bindAddress, InternetAddress.anyIPv4);
    expect(binding.advertiseHost, '192.168.100.50');
  });

  test('prefers a routable address over a link-local one', () async {
    final policy = MediaHostListenPolicy(
      interfaces: () => [
        _interface('en1', ['169.254.7.7']),
        _interface('en0', ['10.0.0.9']),
      ],
    );

    final binding = await policy.resolve(
      endpoint: Uri.parse('http://192.168.100.241:8080/v1'),
    );

    expect(binding!.advertiseHost, '10.0.0.9');
  });

  test('falls back to link-local when nothing else is configured', () async {
    final policy = MediaHostListenPolicy(
      interfaces: () => [
        _interface('en1', ['169.254.7.7']),
      ],
    );

    final binding = await policy.resolve(
      endpoint: Uri.parse('http://192.168.100.241:8080/v1'),
    );

    expect(binding!.advertiseHost, '169.254.7.7');
  });

  test('returns null when no address could reach the endpoint', () async {
    final policy = MediaHostListenPolicy(
      interfaces: () => [
        _interface('ppp0', ['203.0.113.9']),
      ],
    );

    final binding = await policy.resolve(
      endpoint: Uri.parse('https://api.example.com/v1'),
    );

    expect(binding, isNull);
  });
}
