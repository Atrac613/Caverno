import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/utils/bounded_process.dart';
import 'network_address_utils.dart';
import 'network_tool_dependencies.dart';

typedef NetworkReverseLookup =
    Future<InternetAddress> Function(InternetAddress address);

/// Wall-clock budget for a single DNS query issued by the network tools.
///
/// These tools may legitimately leave the LAN, but a resolver stranded behind
/// a dead uplink never answers at all: the OS then waits out its own retry
/// chain and the tool call stalls the turn that made it. Failing the call is
/// always preferable to hanging it.
const Duration dnsQueryTimeout = Duration(seconds: 5);

extension DnsQueryBounds<T> on Future<T> {
  /// Bounds this query by [dnsQueryTimeout], naming [target] on expiry.
  Future<T> dnsBounded(String target) => timeout(
    dnsQueryTimeout,
    onTimeout: () => throw TimeoutException(
      'DNS query for "$target" did not complete within '
      '${dnsQueryTimeout.inSeconds}s. The configured resolver may be '
      'unreachable.',
    ),
  );
}

/// [InternetAddress.lookup] with the shared DNS budget already applied, for
/// callers that hand a [NetworkAddressLookup] to a collaborator.
Future<List<InternetAddress>> boundedAddressLookup(
  String host, {
  InternetAddressType type = InternetAddressType.any,
}) => InternetAddress.lookup(host, type: type).dnsBounded(host);

/// DNS resolution tools exposed to the LLM.
class NetworkDnsTools {
  NetworkDnsTools._();

  static const Set<String> supportedRecordTypes = {'A', 'AAAA', 'PTR', 'CNAME'};

  /// Resolves [host] to IP addresses and returns a JSON-formatted result.
  static Future<String> lookup({required String host}) async {
    final results = await InternetAddress.lookup(host).dnsBounded(host);
    if (results.isEmpty) {
      return jsonEncode({'host': host, 'error': 'No records found'});
    }

    final records = results
        .map(
          (r) => {
            'address': r.address,
            'type': r.type == InternetAddressType.IPv4 ? 'A' : 'AAAA',
            'host': r.host,
          },
        )
        .toList();

    return jsonEncode({'host': host, 'records': records});
  }

  /// Resolves a specific DNS record type for [target].
  static Future<String> query({
    required String target,
    String recordType = 'A',
    NetworkAddressLookup? addressLookup,
    NetworkReverseLookup? reverseLookup,
    NetworkProcessRunner? processRunner,
  }) async {
    final normalizedType = recordType.trim().toUpperCase();
    if (!supportedRecordTypes.contains(normalizedType)) {
      return jsonEncode({
        'error': true,
        'message':
            'record_type must be one of: ${supportedRecordTypes.join(', ')}',
      });
    }

    final records = <Map<String, dynamic>>[];
    switch (normalizedType) {
      case 'A':
      case 'AAAA':
        final lookup = addressLookup ?? InternetAddress.lookup;
        final type = normalizedType == 'A'
            ? InternetAddressType.IPv4
            : InternetAddressType.IPv6;
        final addresses = await lookup(target, type: type).dnsBounded(target);
        final seen = <String>{};
        for (final address in addresses) {
          if (seen.add(address.address)) {
            records.add({
              'type': normalizedType,
              'value': address.address,
              'host': address.host,
            });
          }
        }
        break;
      case 'PTR':
        final literal = InternetAddress.tryParse(
          normalizeNetworkIpForComparison(target),
        );
        if (literal == null) {
          return jsonEncode({
            'error': true,
            'message': 'PTR queries require an IPv4 or IPv6 literal address.',
          });
        }
        final reverse = reverseLookup ?? ((address) => address.reverse());
        final resolved = await reverse(literal).dnsBounded(literal.address);
        records.add({
          'type': normalizedType,
          'value': resolved.host,
          'address': literal.address,
        });
        break;
      case 'CNAME':
        final runner = processRunner ?? runProcessBounded;
        final result = await runner('nslookup', ['-type=cname', target]);
        if (result.exitCode == 0) {
          final matches = RegExp(
            r'canonical name\s*=\s*(\S+)',
            caseSensitive: false,
          ).allMatches(result.stdout as String);
          final seen = <String>{};
          for (final match in matches) {
            final value = match.group(1);
            if (value != null && seen.add(value)) {
              records.add({'type': normalizedType, 'value': value});
            }
          }
        }
        break;
    }

    return jsonEncode({
      'target': target,
      'record_type': normalizedType,
      'records_found': records.length,
      'records': records,
    });
  }
}
