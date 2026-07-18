import 'package:caverno/core/services/lan_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LanIpNetwork parsing', () {
    test('normalizes IPv4 and IPv6 CIDRs to their network addresses', () {
      final ipv4 = LanIpNetwork.parse(' 192.168.4.42/24 ');
      final ipv6 = LanIpNetwork.parse('fd00::42/120');

      expect(ipv4, isNotNull);
      expect(ipv4!.networkAddress, '192.168.4.0');
      expect(ipv4.prefixLength, 24);
      expect(ipv4.cidr, '192.168.4.0/24');
      expect(ipv4.isIpv4, isTrue);
      expect(ipv4.isIpv6, isFalse);

      expect(ipv6, isNotNull);
      expect(ipv6!.networkAddress, 'fd00::');
      expect(ipv6.prefixLength, 120);
      expect(ipv6.cidr, 'fd00::/120');
      expect(ipv6.isIpv4, isFalse);
      expect(ipv6.isIpv6, isTrue);
    });

    test('rejects malformed addresses and out-of-range prefixes', () {
      expect(LanIpNetwork.parse('192.168.1.0'), isNull);
      expect(LanIpNetwork.parse('192.168.1.0/24/extra'), isNull);
      expect(LanIpNetwork.parse('not-an-ip/24'), isNull);
      expect(LanIpNetwork.parse('192.168.1.0/not-a-prefix'), isNull);
      expect(LanIpNetwork.fromIpAndPrefix('192.168.1.1', -1), isNull);
      expect(LanIpNetwork.fromIpAndPrefix('192.168.1.1', 33), isNull);
      expect(LanIpNetwork.fromIpAndPrefix('fd00::1', 129), isNull);
    });
  });

  group('LanIpNetwork enumeration', () {
    test('preserves IPv4 reserved-address rules at prefix boundaries', () {
      final slash30 = LanIpNetwork.parse('192.168.1.0/30')!;
      final slash31 = LanIpNetwork.parse('192.168.1.0/31')!;
      final slash32 = LanIpNetwork.parse('192.168.1.7/32')!;

      expect(slash30.hostCount, 2);
      expect(slash30.enumerableHostIps(), ['192.168.1.1', '192.168.1.2']);
      expect(slash31.hostCount, 2);
      expect(slash31.enumerableHostIps(), ['192.168.1.0', '192.168.1.1']);
      expect(slash32.hostCount, 1);
      expect(slash32.enumerableHostIps(), ['192.168.1.7']);
    });

    test('enumerates small IPv6 ranges without the network address', () {
      final network = LanIpNetwork.parse('fd00::/126')!;

      expect(network.hostCount, 3);
      expect(network.enumerableHostIps(), ['fd00::1', 'fd00::2', 'fd00::3']);
    });

    test('caps host counts and refuses wide IPv6 enumeration', () {
      final ipv4 = LanIpNetwork.parse('10.0.0.0/16')!;
      final ipv6 = LanIpNetwork.parse('fd00::/64')!;

      expect(ipv4.hostCount, LanIpNetwork.maxEnumeratedHosts);
      expect(ipv4.enumerableHostIps(), hasLength(1024));
      expect(ipv4.enumerableHostIps().first, '10.0.0.1');
      expect(ipv4.enumerableHostIps().last, '10.0.4.0');
      expect(ipv6.hostCount, LanIpNetwork.maxEnumeratedHosts);
      expect(ipv6.enumerableHostIps(), isEmpty);
    });
  });

  group('LanIpNetwork address operations', () {
    test('checks containment and rejects mismatched or invalid addresses', () {
      final ipv4 = LanIpNetwork.parse('192.168.1.0/24')!;
      final ipv6 = LanIpNetwork.parse('fe80::/64')!;

      expect(ipv4.contains('192.168.1.99'), isTrue);
      expect(ipv4.contains('192.168.2.1'), isFalse);
      expect(ipv4.contains('fd00::1'), isFalse);
      expect(ipv4.contains('not-an-ip'), isFalse);
      expect(ipv6.contains('fe80::abcd%en0'), isTrue);
      expect(ipv6.contains('fd00::1'), isFalse);
    });

    test('orders addresses numerically and keeps IPv4 before IPv6', () {
      final addresses = ['fd00::1', '192.168.1.10', '192.168.1.2', '10.0.0.1']
        ..sort(LanIpNetwork.compareAddresses);

      expect(addresses, ['10.0.0.1', '192.168.1.2', '192.168.1.10', 'fd00::1']);
      expect(LanIpNetwork.compareAddresses('alpha', 'beta'), lessThan(0));
    });

    test('strips scope IDs and detects IPv6-looking values', () {
      expect(LanIpNetwork.stripScopeId(' fe80::1%en0 '), 'fe80::1');
      expect(LanIpNetwork.stripScopeId('192.168.1.1'), '192.168.1.1');
      expect(LanIpNetwork.looksLikeIpv6('fe80::1%en0'), isTrue);
      expect(LanIpNetwork.looksLikeIpv6('192.168.1.1'), isFalse);
    });
  });
}
