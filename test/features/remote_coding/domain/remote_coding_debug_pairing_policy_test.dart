import 'package:caverno/features/remote_coding/domain/remote_coding_debug_pairing_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteCodingDebugPairingPolicy', () {
    test('a release build never allows a typed pairing code', () {
      // Scanning is a proof of proximity, and pairing confers the desktop's
      // execution authority (SA-26). Typing the code removes the proof.
      const policy = RemoteCodingDebugPairingPolicy(
        isRelease: true,
        isProfile: false,
      );

      expect(policy.allowsManualPairingEntry, isFalse);
    });

    test('a profile build does not either', () {
      // Profile is excluded as well as release because a profile build is a
      // shippable artifact, not a development convenience.
      const policy = RemoteCodingDebugPairingPolicy(
        isRelease: false,
        isProfile: true,
      );

      expect(policy.allowsManualPairingEntry, isFalse);
    });

    test('a debug build allows it', () {
      const policy = RemoteCodingDebugPairingPolicy(
        isRelease: false,
        isProfile: false,
      );

      expect(policy.allowsManualPairingEntry, isTrue);
    });

    test('current() reads the compile flags rather than a mode getter', () {
      // The flags are constructor values so the disabled cases above can be
      // asserted at all; this checks the factory still agrees with the build
      // the suite is running in, which is a debug one.
      final policy = RemoteCodingDebugPairingPolicy.current();

      expect(policy.isRelease, isFalse);
      expect(policy.isProfile, isFalse);
      expect(policy.allowsManualPairingEntry, isTrue);
    });
  });
}
