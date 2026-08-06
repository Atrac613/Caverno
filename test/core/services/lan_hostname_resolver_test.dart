import 'dart:async';

import 'package:caverno/core/services/lan_hostname_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LanHostnameResolver reverse DNS', () {
    test('returns the PTR name when the resolver answers', () async {
      final resolver = LanHostnameResolver(
        reverseDnsLookup: (ip) async => 'raspberrypi.local',
      );

      expect(await resolver.reverseDns('192.168.100.2'), 'raspberrypi.local');
      expect(resolver.isReverseDnsDisabled, isFalse);
    });

    test('drops an answer that is just the address back', () async {
      final resolver = LanHostnameResolver(reverseDnsLookup: (ip) async => ip);

      expect(await resolver.reverseDns('192.168.100.2'), isNull);
    });

    test('caps a hung query instead of waiting out the retry chain', () async {
      final resolver = LanHostnameResolver(
        reverseDnsLookup: (ip) => Completer<String>().future,
        reverseDnsTimeout: const Duration(milliseconds: 50),
      );

      final stopwatch = Stopwatch()..start();
      expect(await resolver.reverseDns('192.168.100.2'), isNull);
      stopwatch.stop();

      // The regression is an unbounded await: the OS resolver retry chain runs
      // for seconds per host when the configured DNS server is unreachable.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('stops querying once the timeout budget is exhausted', () async {
      final queried = <String>[];
      final resolver = LanHostnameResolver(
        reverseDnsLookup: (ip) {
          queried.add(ip);
          return Completer<String>().future;
        },
        reverseDnsTimeout: const Duration(milliseconds: 1),
        reverseDnsTimeoutBudget: 3,
      );

      for (var host = 1; host <= 10; host++) {
        expect(await resolver.reverseDns('192.168.100.$host'), isNull);
      }

      // Only the budget is spent; the remaining hosts skip the resolver
      // entirely and fall back to the link-layer cache and mDNS.
      expect(queried, hasLength(3));
      expect(resolver.isReverseDnsDisabled, isTrue);
      expect(resolver.reverseDnsTimeoutCount, 3);
    });

    test('does not spend budget on a resolver that answers NXDOMAIN', () async {
      final queried = <String>[];
      final resolver = LanHostnameResolver(
        reverseDnsLookup: (ip) {
          queried.add(ip);
          return Future<String>.error(StateError('no PTR record'));
        },
        reverseDnsTimeout: const Duration(milliseconds: 1),
        reverseDnsTimeoutBudget: 3,
      );

      for (var host = 1; host <= 10; host++) {
        expect(await resolver.reverseDns('192.168.100.$host'), isNull);
      }

      expect(queried, hasLength(10));
      expect(resolver.isReverseDnsDisabled, isFalse);
      expect(resolver.reverseDnsTimeoutCount, 0);
    });

    test('reset re-enables queries for the next scan', () async {
      final resolver = LanHostnameResolver(
        reverseDnsLookup: (ip) => Completer<String>().future,
        reverseDnsTimeout: const Duration(milliseconds: 1),
        reverseDnsTimeoutBudget: 1,
      );

      await resolver.reverseDns('192.168.100.2');
      expect(resolver.isReverseDnsDisabled, isTrue);

      resolver.reset();
      expect(resolver.isReverseDnsDisabled, isFalse);
      expect(resolver.reverseDnsTimeoutCount, 0);
    });
  });

  group('LanHostnameResolver source order', () {
    test('prefers reverse DNS over the link-layer name', () async {
      final resolver = LanHostnameResolver(
        reverseDnsLookup: (ip) async => 'from-dns',
      );

      expect(
        await resolver.resolve('192.168.100.2', linkLayerHostname: 'from-arp'),
        'from-dns',
      );
    });

    test('falls back to the link-layer name when DNS is unreachable', () async {
      final resolver = LanHostnameResolver(
        reverseDnsLookup: (ip) => Completer<String>().future,
        reverseDnsTimeout: const Duration(milliseconds: 1),
      );

      expect(
        await resolver.resolve('192.168.100.2', linkLayerHostname: 'from-arp'),
        'from-arp',
      );
    });
  });

  group('LanHostnameResolver.buildReversePointerName', () {
    test('builds in-addr.arpa and ip6.arpa pointers', () {
      expect(
        LanHostnameResolver.buildReversePointerName('192.168.100.2'),
        '2.100.168.192.in-addr.arpa',
      );
      expect(
        LanHostnameResolver.buildReversePointerName('fe80::1%en0'),
        endsWith('.ip6.arpa'),
      );
      expect(LanHostnameResolver.buildReversePointerName('not-an-ip'), isNull);
    });
  });
}
