import 'package:caverno/features/remote_coding/domain/remote_coding_transport_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a wss URL only when a pin is present', () {
    expect(
      RemoteCodingTransportPolicy.websocketUrl(
        host: '192.168.1.10',
        port: 8767,
        certificatePin: 'abc',
      ),
      'wss://192.168.1.10:8767/ws',
    );
    expect(
      () => RemoteCodingTransportPolicy.websocketUrl(
        host: '192.168.1.10',
        port: 8767,
        certificatePin: '',
      ),
      throwsA(isA<RemoteCodingPlaintextDowngradeException>()),
    );
  });

  test('refuses credentials on plaintext or a missing pin', () {
    expect(
      () => RemoteCodingTransportPolicy.ensureConfidentialBeforeCredentials(
        url: 'ws://192.168.1.10:8767/ws',
        certificatePin: 'abc',
      ),
      throwsA(isA<RemoteCodingPlaintextDowngradeException>()),
    );
    expect(
      () => RemoteCodingTransportPolicy.ensureConfidentialBeforeCredentials(
        url: 'wss://192.168.1.10:8767/ws',
        certificatePin: '',
      ),
      throwsA(isA<RemoteCodingPlaintextDowngradeException>()),
    );
    expect(
      () => RemoteCodingTransportPolicy.ensureConfidentialBeforeCredentials(
        url: 'wss://192.168.1.10:8767/ws',
        certificatePin: 'abc',
      ),
      returnsNormally,
    );
  });
}
