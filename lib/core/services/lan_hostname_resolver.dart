import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import '../utils/logger.dart';
import 'lan_ip_network.dart';

typedef LanReverseDnsLookup = Future<String> Function(String ip);

/// Resolves a name for a scanned LAN address, cheapest source first: unicast
/// reverse DNS, then the link-layer cache, then mDNS.
///
/// Only the first step can leave the LAN, and that is the step that fails
/// badly. A resolver able to answer for the local subnet replies in
/// single-digit milliseconds, but the common default is a public resolver such
/// as `8.8.8.8`; behind a dead uplink it never replies at all and the OS waits
/// out its own retry chain (measured at 5-10s per query). Multiplied by every
/// live host that turns a LAN-only scan into a multi-minute stall, so each
/// query is capped and the scan stops asking once the resolver has proven
/// unreachable.
class LanHostnameResolver {
  LanHostnameResolver({
    LanReverseDnsLookup? reverseDnsLookup,
    this.reverseDnsTimeout = defaultReverseDnsTimeout,
    this.reverseDnsTimeoutBudget = defaultReverseDnsTimeoutBudget,
  }) : _reverseDnsLookup = reverseDnsLookup ?? _systemReverseLookup;

  static const Duration defaultReverseDnsTimeout = Duration(milliseconds: 600);

  /// Timeouts tolerated before the rest of the scan stops issuing PTR queries.
  /// Networks with no resolver for the local subnet then pay the budget once
  /// instead of once per host, and naming falls back to the link-layer cache
  /// and mDNS, neither of which leaves the LAN.
  static const int defaultReverseDnsTimeoutBudget = 3;

  static Future<String> _systemReverseLookup(String ip) async =>
      (await InternetAddress(ip).reverse()).host;

  final LanReverseDnsLookup _reverseDnsLookup;
  final Duration reverseDnsTimeout;
  final int reverseDnsTimeoutBudget;

  int _reverseDnsTimeouts = 0;
  bool _reverseDnsDisabled = false;

  /// Whether the budget is spent and PTR queries are being skipped.
  bool get isReverseDnsDisabled => _reverseDnsDisabled;

  int get reverseDnsTimeoutCount => _reverseDnsTimeouts;

  /// Clears the budget. Call once per scan so a transient outage does not
  /// disable reverse DNS for the lifetime of the service.
  void reset() {
    _reverseDnsTimeouts = 0;
    _reverseDnsDisabled = false;
  }

  /// Returns the best available name for [ip], or null when no source knows it.
  Future<String?> resolve(
    String ip, {
    String? linkLayerHostname,
    int mdnsTimeoutMs = 2000,
  }) async {
    return await reverseDns(ip) ??
        linkLayerHostname ??
        await mdnsReverse(ip, timeoutMs: mdnsTimeoutMs);
  }

  /// Unicast reverse DNS, bounded by [reverseDnsTimeout] and the shared budget.
  Future<String?> reverseDns(String ip) async {
    if (_reverseDnsDisabled) return null;

    try {
      final host = await _reverseDnsLookup(ip).timeout(reverseDnsTimeout);
      return host != ip && host.isNotEmpty ? host : null;
    } on TimeoutException {
      _noteReverseDnsTimeout();
      return null;
    } catch (_) {
      // A resolved NXDOMAIN is cheap and says nothing about reachability, so
      // it must not count against the timeout budget.
      return null;
    }
  }

  /// Reverse lookup over multicast DNS, which is answered on the LAN itself.
  Future<String?> mdnsReverse(String ip, {int timeoutMs = 2000}) async {
    final ptrName = buildReversePointerName(ip);
    if (ptrName == null) return null;

    MDnsClient? client;
    try {
      client = MDnsClient();
      await client.start();

      final ptr = await client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(ptrName))
          .first
          .timeout(Duration(milliseconds: timeoutMs));
      return ptr.domainName;
    } catch (_) {
      return null;
    } finally {
      client?.stop();
    }
  }

  /// Builds the `in-addr.arpa` / `ip6.arpa` pointer name for [ip].
  static String? buildReversePointerName(String ip) {
    final address = InternetAddress.tryParse(LanIpNetwork.stripScopeId(ip));
    if (address == null) {
      return null;
    }

    if (address.type == InternetAddressType.IPv4) {
      final octets = address.address.split('.').reversed.join('.');
      return '$octets.in-addr.arpa';
    }

    final hex = address.rawAddress
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final reversedNibbles = hex.split('').reversed.join('.');
    return '$reversedNibbles.ip6.arpa';
  }

  void _noteReverseDnsTimeout() {
    _reverseDnsTimeouts++;
    if (_reverseDnsTimeouts < reverseDnsTimeoutBudget || _reverseDnsDisabled) {
      return;
    }
    _reverseDnsDisabled = true;
    appLog(
      '[LanHostnameResolver] Reverse DNS unreachable '
      '($_reverseDnsTimeouts timeouts); skipping PTR queries for the rest of '
      'this scan',
    );
  }
}
