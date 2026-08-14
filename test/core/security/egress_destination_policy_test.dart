import 'dart:io';

import 'package:caverno/core/security/egress_destination_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = EgressDestinationPolicy();

  group('EgressDestinationPolicy URI validation', () {
    test('accepts absolute public HTTP and HTTPS URI shapes', () {
      expect(
        policy.validateUri(Uri.parse('https://example.com/path?q=1')),
        Uri.parse('https://example.com/path?q=1'),
      );
      expect(
        policy.validateUri(Uri.parse('http://93.184.216.34:8080/')),
        Uri.parse('http://93.184.216.34:8080/'),
      );
    });

    test('rejects unsafe schemes, missing hosts, and embedded credentials', () {
      final cases = <String, String>{
        'file:///etc/passwd': 'unsafe_scheme',
        'data:text/plain,secret': 'unsafe_scheme',
        'about:blank': 'unsafe_scheme',
        'javascript:alert(1)': 'unsafe_scheme',
        '/relative': 'missing_host',
        'https:///missing-host': 'missing_host',
        'https://user:secret@example.com/': 'embedded_credentials',
      };

      for (final entry in cases.entries) {
        expect(
          () => policy.validateUri(Uri.parse(entry.key)),
          throwsA(
            isA<EgressPolicyException>().having(
              (error) => error.code,
              'code',
              entry.value,
            ),
          ),
          reason: entry.key,
        );
      }
    });
  });

  group('EgressDestinationPolicy address validation', () {
    test('accepts representative public IPv4 and IPv6 addresses', () {
      for (final value in [
        '1.1.1.1',
        '8.8.8.8',
        '93.184.216.34',
        '2606:4700:4700::1111',
        '2001:4860:4860::8888',
      ]) {
        expect(
          policy.isSafeAddress(InternetAddress(value)),
          isTrue,
          reason: value,
        );
      }
    });

    test('rejects unsafe IPv4 ranges', () {
      for (final value in [
        '0.0.0.0',
        '10.0.0.1',
        '100.64.0.1',
        '127.0.0.1',
        '169.254.169.254',
        '172.16.0.1',
        '192.0.2.1',
        '192.168.1.1',
        '198.18.0.1',
        '198.51.100.1',
        '203.0.113.1',
        '224.0.0.1',
        '240.0.0.1',
        '255.255.255.255',
      ]) {
        expect(
          policy.isSafeAddress(InternetAddress(value)),
          isFalse,
          reason: value,
        );
      }
    });

    test('rejects unsafe IPv6 and mapped IPv4 ranges', () {
      for (final value in [
        '::',
        '::1',
        '::ffff:127.0.0.1',
        '::ffff:169.254.169.254',
        '64:ff9b::7f00:1',
        '100::1',
        '2001:2::1',
        '2001:db8::1',
        '2002:7f00:1::',
        'fc00::1',
        'fd00:ec2::254',
        'fe80::1',
        'ff02::1',
      ]) {
        expect(
          policy.isSafeAddress(InternetAddress(value)),
          isFalse,
          reason: value,
        );
      }
    });

    test('accepts mapped public IPv4 only', () {
      expect(policy.isSafeAddress(InternetAddress('::ffff:8.8.8.8')), isTrue);
      expect(policy.isSafeAddress(InternetAddress('64:ff9b::808:808')), isTrue);
    });
  });

  group('EgressDestinationPolicy resolution and peer binding', () {
    final uri = Uri.parse('https://example.com/resource');

    test('approves only a non-empty all-safe DNS answer set', () {
      final approved = policy.approveResolvedAddresses(uri, [
        InternetAddress('93.184.216.34'),
        InternetAddress('2606:2800:220:1:248:1893:25c8:1946'),
      ]);

      expect(approved.uri, uri);
      expect(approved.address.address, '93.184.216.34');

      expect(
        () => policy.approveResolvedAddresses(uri, const []),
        throwsA(
          isA<EgressPolicyException>().having(
            (error) => error.code,
            'code',
            'empty_dns_answer',
          ),
        ),
      );
    });

    test('rejects mixed public and private DNS answers', () {
      expect(
        () => policy.approveResolvedAddresses(uri, [
          InternetAddress('93.184.216.34'),
          InternetAddress('127.0.0.1'),
        ]),
        throwsA(
          isA<EgressPolicyException>().having(
            (error) => error.code,
            'code',
            'unsafe_address',
          ),
        ),
      );
    });

    test('requires the connected peer to match an approved answer', () {
      final approved = policy.approveResolvedAddresses(uri, [
        InternetAddress('93.184.216.34'),
      ]);

      expect(
        () => policy.verifyPeer(approved, InternetAddress('93.184.216.34')),
        returnsNormally,
      );
      expect(
        () => policy.verifyPeer(approved, InternetAddress('93.184.216.35')),
        throwsA(
          isA<EgressPolicyException>().having(
            (error) => error.code,
            'code',
            'peer_mismatch',
          ),
        ),
      );
    });
  });

  group('EgressDestinationPolicy redirect headers', () {
    test('preserves headers for the same origin', () {
      final headers = {
        'Authorization': 'Bearer secret',
        'Cookie': 'session=secret',
        'X-Trace': 'keep',
      };

      expect(
        policy.headersForRedirect(
          headers,
          from: Uri.parse('https://example.com/start'),
          to: Uri.parse('https://EXAMPLE.com:443/next'),
        ),
        headers,
      );
    });

    test('strips sensitive headers when the origin changes', () {
      expect(
        policy.headersForRedirect(
          {
            'Authorization': 'Bearer secret',
            'COOKIE': 'session=secret',
            'Proxy-Authorization': 'Basic secret',
            'X-Trace': 'keep',
          },
          from: Uri.parse('https://example.com/start'),
          to: Uri.parse('https://other.example.com/next'),
        ),
        {'X-Trace': 'keep'},
      );
    });

    test('treats scheme and effective port changes as cross-origin', () {
      expect(
        policy.isSameOrigin(
          Uri.parse('http://example.com/'),
          Uri.parse('https://example.com/'),
        ),
        isFalse,
      );
      expect(
        policy.isSameOrigin(
          Uri.parse('https://example.com/'),
          Uri.parse('https://example.com:444/'),
        ),
        isFalse,
      );
    });
  });
}
