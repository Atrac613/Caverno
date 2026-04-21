import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ping/dart_ping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../utils/logger.dart';

typedef LanStringProvider = Future<String?> Function();
typedef LanProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef LanHostProbe =
    Future<LanHost?> Function({
      required String ip,
      required int timeoutMs,
      required List<int> ports,
      required Map<String, LanLinkLayerEntry> linkLayerTable,
    });

/// Discovered host on the local network.
class LanHost {
  const LanHost({
    required this.ip,
    this.hostname,
    this.mac,
    this.vendor,
    this.responseTimeMs,
    this.openPorts = const [],
  });

  final String ip;
  final String? hostname;
  final String? mac;
  final String? vendor;
  final double? responseTimeMs;
  final List<int> openPorts;

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'ip_version': LanIpNetwork.looksLikeIpv6(ip) ? 'ipv6' : 'ipv4',
    if (hostname != null) 'hostname': hostname,
    if (mac != null) 'mac': mac,
    if (vendor != null) 'vendor': vendor,
    if (responseTimeMs != null) 'response_time_ms': responseTimeMs,
    if (openPorts.isNotEmpty) 'open_ports': openPorts,
  };
}

/// Cached link-layer metadata for a discovered IP address.
class LanLinkLayerEntry {
  const LanLinkLayerEntry({this.mac, this.hostname, this.interfaceName});

  final String? mac;
  final String? hostname;
  final String? interfaceName;
}

/// Represents an IPv4 or IPv6 CIDR network.
class LanIpNetwork {
  LanIpNetwork._({
    required this.networkAddress,
    required this.prefixLength,
    required this.addressType,
    required BigInt firstValue,
    required BigInt lastValue,
  }) : _firstValue = firstValue,
       _lastValue = lastValue;

  static const int maxEnumeratedHosts = 1024;

  final String networkAddress;
  final int prefixLength;
  final InternetAddressType addressType;
  final BigInt _firstValue;
  final BigInt _lastValue;

  bool get isIpv4 => addressType == InternetAddressType.IPv4;
  bool get isIpv6 => addressType == InternetAddressType.IPv6;
  int get _bitLength => isIpv4 ? 32 : 128;

  String get cidr => '$networkAddress/$prefixLength';

  int get hostCount {
    final usable = _usableHostCount;
    final capped = usable > BigInt.from(maxEnumeratedHosts)
        ? BigInt.from(maxEnumeratedHosts)
        : usable;
    return capped.toInt();
  }

  List<String> enumerableHostIps() {
    final usable = _usableHostCount;
    if (usable <= BigInt.zero) {
      return const [];
    }
    if (isIpv6 && usable > BigInt.from(maxEnumeratedHosts)) {
      return const [];
    }

    final start = _enumerationStart;
    final limit = hostCount;
    final results = <String>[];
    for (var index = 0; index < limit; index += 1) {
      final current = start + BigInt.from(index);
      if (current > _lastValue) {
        break;
      }
      results.add(_bigIntToAddressString(current, addressType));
    }
    return results;
  }

  bool contains(String ip) {
    final address = _tryParseLiteral(ip);
    if (address == null || address.type != addressType) {
      return false;
    }
    final value = _addressToBigInt(address);
    return value >= _firstValue && value <= _lastValue;
  }

  static LanIpNetwork? parse(String cidr) {
    final parts = cidr.trim().split('/');
    if (parts.length != 2) {
      return null;
    }

    final prefix = int.tryParse(parts[1]);
    if (prefix == null) {
      return null;
    }

    return fromIpAndPrefix(parts[0], prefix);
  }

  static LanIpNetwork? fromIpAndPrefix(String ip, int prefix) {
    final address = _tryParseLiteral(ip);
    if (address == null) {
      return null;
    }

    final bitLength = address.type == InternetAddressType.IPv4 ? 32 : 128;
    if (prefix < 0 || prefix > bitLength) {
      return null;
    }

    final allOnes = (BigInt.one << bitLength) - BigInt.one;
    final hostBits = bitLength - prefix;
    final hostMask = hostBits == 0
        ? BigInt.zero
        : (BigInt.one << hostBits) - BigInt.one;
    final networkMask = allOnes ^ hostMask;
    final addressValue = _addressToBigInt(address);
    final firstValue = addressValue & networkMask;
    final lastValue = firstValue | hostMask;

    return LanIpNetwork._(
      networkAddress: _bigIntToAddressString(firstValue, address.type),
      prefixLength: prefix,
      addressType: address.type,
      firstValue: firstValue,
      lastValue: lastValue,
    );
  }

  static int compareAddresses(String a, String b) {
    final aAddress = _tryParseLiteral(a);
    final bAddress = _tryParseLiteral(b);

    if (aAddress == null || bAddress == null) {
      return a.compareTo(b);
    }
    if (aAddress.type != bAddress.type) {
      return aAddress.type == InternetAddressType.IPv4 ? -1 : 1;
    }

    final aBytes = aAddress.rawAddress;
    final bBytes = bAddress.rawAddress;
    final length = aBytes.length < bBytes.length
        ? aBytes.length
        : bBytes.length;

    for (var index = 0; index < length; index += 1) {
      final diff = aBytes[index] - bBytes[index];
      if (diff != 0) {
        return diff;
      }
    }

    return a.compareTo(b);
  }

  static String stripScopeId(String value) {
    final trimmed = value.trim();
    final separatorIndex = trimmed.indexOf('%');
    return separatorIndex >= 0 ? trimmed.substring(0, separatorIndex) : trimmed;
  }

  static bool looksLikeIpv6(String value) => stripScopeId(value).contains(':');

  BigInt get _usableHostCount {
    final total = _lastValue - _firstValue + BigInt.one;
    if (isIpv4 && prefixLength <= 30) {
      return total - BigInt.from(2);
    }
    if (isIpv6 && prefixLength < _bitLength) {
      return total - BigInt.one;
    }
    return total;
  }

  BigInt get _enumerationStart {
    if (isIpv4 && prefixLength <= 30) {
      return _firstValue + BigInt.one;
    }
    if (isIpv6 && prefixLength < _bitLength) {
      return _firstValue + BigInt.one;
    }
    return _firstValue;
  }

  static InternetAddress? _tryParseLiteral(String value) {
    final stripped = stripScopeId(value);
    if (stripped.isEmpty) {
      return null;
    }
    return InternetAddress.tryParse(stripped);
  }

  static BigInt _addressToBigInt(InternetAddress address) {
    var result = BigInt.zero;
    for (final byte in address.rawAddress) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  static String _bigIntToAddressString(
    BigInt value,
    InternetAddressType addressType,
  ) {
    final byteCount = addressType == InternetAddressType.IPv4 ? 4 : 16;
    final bytes = Uint8List(byteCount);
    var remaining = value;

    for (var index = byteCount - 1; index >= 0; index -= 1) {
      bytes[index] = (remaining & BigInt.from(0xFF)).toInt();
      remaining = remaining >> 8;
    }

    return InternetAddress.fromRawAddress(bytes).address;
  }
}

enum _LanIpVersionPreference { auto, ipv4, ipv6 }

/// Manages LAN scanning: ping sweep, port probing, reverse DNS, and ARP/NDP.
class LanScanService {
  LanScanService({
    LanStringProvider? wifiIpv4Provider,
    LanStringProvider? wifiIpv6Provider,
    LanStringProvider? wifiSubmaskProvider,
    LanProcessRunner? processRunner,
    LanHostProbe? hostProbe,
  }) : _wifiIpv4Provider = wifiIpv4Provider,
       _wifiIpv6Provider = wifiIpv6Provider,
       _wifiSubmaskProvider = wifiSubmaskProvider,
       _processRunner = processRunner,
       _hostProbe = hostProbe;

  final NetworkInfo _networkInfo = NetworkInfo();
  final LanStringProvider? _wifiIpv4Provider;
  final LanStringProvider? _wifiIpv6Provider;
  final LanStringProvider? _wifiSubmaskProvider;
  final LanProcessRunner? _processRunner;
  final LanHostProbe? _hostProbe;

  List<LanHost> _scanResults = [];

  /// Maximum hosts to ping concurrently to avoid socket exhaustion.
  static const int _concurrencyLimit = 50;

  /// Default ports to probe on each discovered host.
  static const List<int> _defaultPorts = [22, 80, 443, 8080];

  /// Trigger a LAN scan and return the results as a JSON string.
  Future<String> startScan({
    String? subnet,
    String? ipVersion,
    int timeoutMs = 1000,
    List<int>? ports,
  }) async {
    final effectiveTimeout = timeoutMs.clamp(100, 5000);
    final effectivePorts = _clampPorts(ports ?? _defaultPorts);
    final versionPreference = _parseIpVersionPreference(ipVersion);
    final linkLayerTable = await _fetchLinkLayerTable();
    final planResult = await _buildScanPlan(
      userSubnet: subnet?.trim(),
      versionPreference: versionPreference,
      linkLayerTable: linkLayerTable,
    );

    if (planResult.plan == null) {
      return jsonEncode({
        'error': true,
        'message':
            planResult.errorMessage ??
            _defaultNoTargetMessage(versionPreference),
      });
    }

    final scanPlan = planResult.plan!;
    appLog(
      '[LanScanService] Starting scan: ${scanPlan.summaryLabel} '
      '(${scanPlan.hostCount} hosts, timeout=${effectiveTimeout}ms, '
      'ports=$effectivePorts, strategy=${scanPlan.strategy})',
    );

    final discovered = <LanHost>[];
    final allIps = scanPlan.candidateIps;

    for (var index = 0; index < allIps.length; index += _concurrencyLimit) {
      final batch = allIps.sublist(
        index,
        (index + _concurrencyLimit).clamp(0, allIps.length),
      );
      final results = await Future.wait(
        batch.map(
          (ip) => _probeHost(
            ip: ip,
            timeoutMs: effectiveTimeout,
            ports: effectivePorts,
            linkLayerTable: linkLayerTable,
          ),
        ),
      );
      for (final host in results) {
        if (host != null) {
          discovered.add(host);
        }
      }
    }

    discovered.sort((a, b) => LanIpNetwork.compareAddresses(a.ip, b.ip));
    _scanResults = discovered;

    appLog('[LanScanService] Scan complete: ${discovered.length} hosts found');

    return jsonEncode({
      'subnet': scanPlan.summaryLabel,
      'hosts_scanned': scanPlan.hostCount,
      'hosts_found': discovered.length,
      'address_families': scanPlan.addressFamilies,
      'scan_strategy': scanPlan.strategy,
      'hosts': discovered.map((host) => host.toJson()).toList(),
    });
  }

  /// Return cached scan results, optionally sorted.
  String getScanResults({String? sortBy}) {
    if (_scanResults.isEmpty) {
      return jsonEncode({
        'hosts': <Map<String, dynamic>>[],
        'message': 'No cached scan results. Call lan_scan first.',
      });
    }

    final sorted = List<LanHost>.from(_scanResults);
    switch (sortBy) {
      case 'response_time':
        sorted.sort((a, b) {
          final aTime = a.responseTimeMs ?? double.infinity;
          final bTime = b.responseTimeMs ?? double.infinity;
          return aTime.compareTo(bTime);
        });
        break;
      case 'hostname':
        sorted.sort((a, b) {
          final aName = a.hostname ?? '';
          final bName = b.hostname ?? '';
          return aName.compareTo(bName);
        });
        break;
      default:
        sorted.sort((a, b) => LanIpNetwork.compareAddresses(a.ip, b.ip));
    }

    return jsonEncode({
      'hosts_found': sorted.length,
      'hosts': sorted.map((host) => host.toJson()).toList(),
    });
  }

  Future<void> dispose() async {
    _scanResults.clear();
  }

  Future<LanHost?> _probeHost({
    required String ip,
    required int timeoutMs,
    required List<int> ports,
    required Map<String, LanLinkLayerEntry> linkLayerTable,
  }) async {
    final overrideProbe = _hostProbe;
    if (overrideProbe != null) {
      return overrideProbe(
        ip: ip,
        timeoutMs: timeoutMs,
        ports: ports,
        linkLayerTable: linkLayerTable,
      );
    }

    final timeoutSec = (timeoutMs / 1000).ceil().clamp(1, 10);
    final lookupIp = LanIpNetwork.stripScopeId(ip);
    final linkEntry = linkLayerTable[ip] ?? linkLayerTable[lookupIp];

    double? responseTimeMs;
    var alive = false;

    try {
      final ping = Ping(ip, count: 1, timeout: timeoutSec);
      await for (final event in ping.stream) {
        if (event.response != null && event.response!.time != null) {
          responseTimeMs = event.response!.time!.inMicroseconds / 1000.0;
          alive = true;
        }
        break;
      }
    } catch (_) {
      // Fall back to TCP probing below.
    }

    if (!alive) {
      final tcpResult = await _quickTcpProbe(
        ip: ip,
        ports: ports.isEmpty ? [80, 443] : [ports.first],
        timeoutMs: timeoutMs,
      );
      if (tcpResult != null) {
        alive = true;
        responseTimeMs = tcpResult;
      }
    }

    if (!alive) {
      return null;
    }

    final openPorts = await _scanPorts(
      ip: ip,
      ports: ports,
      timeoutMs: timeoutMs,
    );

    String? hostname;
    try {
      final reverse = await InternetAddress(lookupIp).reverse();
      if (reverse.host != lookupIp) {
        hostname = reverse.host;
      }
    } catch (_) {
      // Reverse DNS is optional.
    }

    if (hostname == null && linkEntry?.hostname != null) {
      hostname = linkEntry!.hostname;
    }

    hostname ??= await _mdnsReverseLookup(lookupIp, timeoutMs: timeoutMs);

    return LanHost(
      ip: ip,
      hostname: hostname,
      mac: linkEntry?.mac,
      responseTimeMs: responseTimeMs != null
          ? double.parse(responseTimeMs.toStringAsFixed(2))
          : null,
      openPorts: openPorts,
    );
  }

  Future<double?> _quickTcpProbe({
    required String ip,
    required List<int> ports,
    required int timeoutMs,
  }) async {
    for (final port in ports) {
      try {
        final stopwatch = Stopwatch()..start();
        final socket = await Socket.connect(
          ip,
          port,
          timeout: Duration(milliseconds: timeoutMs),
        );
        stopwatch.stop();
        socket.destroy();
        return stopwatch.elapsedMicroseconds / 1000.0;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<List<int>> _scanPorts({
    required String ip,
    required List<int> ports,
    required int timeoutMs,
  }) async {
    if (ports.isEmpty) {
      return [];
    }

    final results = await Future.wait(
      ports.map((port) async {
        try {
          final socket = await Socket.connect(
            ip,
            port,
            timeout: Duration(milliseconds: timeoutMs),
          );
          socket.destroy();
          return port;
        } catch (_) {
          return -1;
        }
      }),
    );

    return results.where((port) => port > 0).toList()..sort();
  }

  Future<_ScanPlanResult> _buildScanPlan({
    required String? userSubnet,
    required _LanIpVersionPreference versionPreference,
    required Map<String, LanLinkLayerEntry> linkLayerTable,
  }) async {
    if (userSubnet != null && userSubnet.isNotEmpty) {
      final network = LanIpNetwork.parse(userSubnet);
      if (network == null) {
        return const _ScanPlanResult.error(
          'Invalid subnet. Use CIDR notation like 192.168.1.0/24 or fd00::/120.',
        );
      }

      final directCandidates = network.enumerableHostIps();
      if (directCandidates.isNotEmpty) {
        return _ScanPlanResult.success(
          _ScanPlan(
            candidateIps: directCandidates,
            summaryLabel: network.cidr,
            hostCount: directCandidates.length,
            addressFamilies: [network.isIpv6 ? 'ipv6' : 'ipv4'],
            strategy: network.isIpv6
                ? 'explicit_ipv6_cidr'
                : 'explicit_ipv4_cidr',
          ),
        );
      }

      if (network.isIpv6) {
        final candidates =
            linkLayerTable.keys
                .where(network.contains)
                .where(_shouldIncludeDiscoveredIpv6Address)
                .toSet()
                .toList(growable: false)
              ..sort(LanIpNetwork.compareAddresses);

        if (candidates.isNotEmpty) {
          return _ScanPlanResult.success(
            _ScanPlan(
              candidateIps: candidates,
              summaryLabel: network.cidr,
              hostCount: candidates.length,
              addressFamilies: const ['ipv6'],
              strategy: 'ipv6_neighbor_table_filtered',
            ),
          );
        }

        return _ScanPlanResult.error(
          'IPv6 subnet $userSubnet is too large to scan directly. Use a '
          'smaller range such as /120 or omit subnet to rely on neighbor '
          'discovery.',
        );
      }

      return _ScanPlanResult.success(
        _ScanPlan(
          candidateIps: directCandidates,
          summaryLabel: network.cidr,
          hostCount: directCandidates.length,
          addressFamilies: const ['ipv4'],
          strategy: 'explicit_ipv4_cidr',
        ),
      );
    }

    final candidates = <String>{};
    final addressFamilies = <String>{};
    final labels = <String>[];
    final strategies = <String>[];

    if (versionPreference != _LanIpVersionPreference.ipv6) {
      final ipv4Network = await _resolveAutoIpv4Network();
      if (ipv4Network != null) {
        candidates.addAll(ipv4Network.enumerableHostIps());
        addressFamilies.add('ipv4');
        labels.add(ipv4Network.cidr);
        strategies.add('ipv4_subnet');
      }
    }

    if (versionPreference != _LanIpVersionPreference.ipv4) {
      final ipv6Candidates = await _resolveAutoIpv6Candidates(linkLayerTable);
      if (ipv6Candidates.isNotEmpty) {
        candidates.addAll(ipv6Candidates);
        addressFamilies.add('ipv6');
        strategies.add('ipv6_neighbors');

        final localIpv6 = await _getWifiIpv6();
        if (localIpv6 != null && localIpv6.trim().isNotEmpty) {
          final localNetwork = LanIpNetwork.fromIpAndPrefix(localIpv6, 64);
          labels.add(localNetwork?.cidr ?? 'ipv6-neighbors');
        } else {
          labels.add('ipv6-neighbors');
        }
      }
    }

    if (candidates.isEmpty) {
      return _ScanPlanResult.error(_defaultNoTargetMessage(versionPreference));
    }

    final sortedCandidates = candidates.toList(growable: false)
      ..sort(LanIpNetwork.compareAddresses);

    return _ScanPlanResult.success(
      _ScanPlan(
        candidateIps: sortedCandidates,
        summaryLabel: labels.join(', '),
        hostCount: sortedCandidates.length,
        addressFamilies: addressFamilies.toList(growable: false)..sort(),
        strategy: strategies.join('+'),
      ),
    );
  }

  Future<LanIpNetwork?> _resolveAutoIpv4Network() async {
    try {
      final ip = await _getWifiIpv4();
      final mask = await _getWifiSubmask();

      if (ip == null || ip.isEmpty) {
        return null;
      }

      final prefix = mask != null && mask.isNotEmpty
          ? _subnetMaskToPrefix(mask)
          : 24;

      return LanIpNetwork.fromIpAndPrefix(ip, prefix);
    } catch (error) {
      appLog('[LanScanService] Failed to auto-detect IPv4 subnet: $error');
      return null;
    }
  }

  Future<Set<String>> _resolveAutoIpv6Candidates(
    Map<String, LanLinkLayerEntry> linkLayerTable,
  ) async {
    try {
      final localIpv6 = await _getWifiIpv6();
      if (localIpv6 == null || localIpv6.trim().isEmpty) {
        return const {};
      }

      final localNetwork = LanIpNetwork.fromIpAndPrefix(localIpv6, 64);
      final localAddress = LanIpNetwork.stripScopeId(localIpv6);
      final candidates = <String>{};

      for (final ip in linkLayerTable.keys) {
        if (!_shouldIncludeDiscoveredIpv6Address(ip)) {
          continue;
        }

        final normalizedIp = LanIpNetwork.stripScopeId(ip);
        if (normalizedIp == localAddress) {
          continue;
        }

        if (_isLinkLocalIpv6(ip) ||
            localNetwork == null ||
            localNetwork.contains(ip)) {
          candidates.add(ip);
        }
      }

      return candidates;
    } catch (error) {
      appLog('[LanScanService] Failed to auto-detect IPv6 neighbors: $error');
      return const {};
    }
  }

  Future<Map<String, LanLinkLayerEntry>> _fetchLinkLayerTable() async {
    final table = <String, LanLinkLayerEntry>{};
    table.addAll(await _fetchArpTable());
    table.addAll(await _fetchIpv6NeighborTable());
    return table;
  }

  Future<Map<String, LanLinkLayerEntry>> _fetchArpTable() async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return const {};
    }

    try {
      final result = await _runProcess('arp', ['-a']);
      if (result.exitCode != 0) {
        return const {};
      }

      final table = <String, LanLinkLayerEntry>{};
      final lines = (result.stdout as String).split('\n');
      final regex = RegExp(
        r'(\S+)\s+\((\d+\.\d+\.\d+\.\d+)\)\s+at\s+([0-9a-fA-F:]+)',
      );

      for (final line in lines) {
        final match = regex.firstMatch(line);
        if (match == null) {
          continue;
        }

        final rawHostname = match.group(1)!;
        final ip = match.group(2)!;
        final mac = match.group(3)!;
        if (mac == '(incomplete)' || mac == 'ff:ff:ff:ff:ff:ff') {
          continue;
        }

        table[ip] = LanLinkLayerEntry(
          mac: mac.toLowerCase(),
          hostname: (rawHostname != '?' && rawHostname != ip)
              ? rawHostname
              : null,
        );
      }

      appLog('[LanScanService] ARP table: ${table.length} IPv4 entries');
      return table;
    } catch (error) {
      appLog('[LanScanService] ARP table fetch failed: $error');
      return const {};
    }
  }

  Future<Map<String, LanLinkLayerEntry>> _fetchIpv6NeighborTable() async {
    if (Platform.isMacOS) {
      return _fetchMacOsIpv6Neighbors();
    }
    if (Platform.isLinux) {
      return _fetchLinuxIpv6Neighbors();
    }
    return const {};
  }

  Future<Map<String, LanLinkLayerEntry>> _fetchMacOsIpv6Neighbors() async {
    try {
      final result = await _runProcess('ndp', ['-an']);
      if (result.exitCode != 0) {
        return const {};
      }

      final table = <String, LanLinkLayerEntry>{};
      final lines = (result.stdout as String).split('\n');
      final regex = RegExp(
        r'^([0-9a-fA-F:%.]+)\s+([0-9a-fA-F:]+|\(incomplete\))\s+(\S+)',
      );

      for (final line in lines) {
        final match = regex.firstMatch(line.trim());
        if (match == null) {
          continue;
        }

        final rawIp = match.group(1)!;
        final rawMac = match.group(2)!;
        final interfaceName = match.group(3)!;
        if (rawMac == '(incomplete)' || rawMac == 'ff:ff:ff:ff:ff:ff') {
          continue;
        }

        final ip = _withScopeIfNeeded(rawIp, interfaceName);
        table[ip] = LanLinkLayerEntry(
          mac: rawMac.toLowerCase(),
          interfaceName: interfaceName,
        );
      }

      appLog('[LanScanService] NDP table: ${table.length} IPv6 entries');
      return table;
    } catch (error) {
      appLog('[LanScanService] macOS NDP fetch failed: $error');
      return const {};
    }
  }

  Future<Map<String, LanLinkLayerEntry>> _fetchLinuxIpv6Neighbors() async {
    try {
      final result = await _runProcess('ip', ['-6', 'neighbor', 'show']);
      if (result.exitCode != 0) {
        return const {};
      }

      final table = <String, LanLinkLayerEntry>{};
      final lines = (result.stdout as String).split('\n');
      final regex = RegExp(
        r'^([0-9a-fA-F:%.]+)\s+dev\s+(\S+)(?:\s+lladdr\s+([0-9a-fA-F:]+))?',
      );

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty ||
            trimmed.contains('FAILED') ||
            trimmed.contains('INCOMPLETE')) {
          continue;
        }

        final match = regex.firstMatch(trimmed);
        if (match == null) {
          continue;
        }

        final rawIp = match.group(1)!;
        final interfaceName = match.group(2)!;
        final rawMac = match.group(3);
        final ip = _withScopeIfNeeded(rawIp, interfaceName);
        table[ip] = LanLinkLayerEntry(
          mac: rawMac?.toLowerCase(),
          interfaceName: interfaceName,
        );
      }

      appLog('[LanScanService] IPv6 neighbors: ${table.length} entries');
      return table;
    } catch (error) {
      appLog('[LanScanService] Linux IPv6 neighbor fetch failed: $error');
      return const {};
    }
  }

  Future<String?> _mdnsReverseLookup(String ip, {int timeoutMs = 2000}) async {
    final ptrName = _buildReversePointerName(ip);
    if (ptrName == null) {
      return null;
    }

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

  List<int> _clampPorts(List<int> ports) {
    return ports.where((port) => port > 0 && port <= 65535).take(20).toList();
  }

  Future<String?> _getWifiIpv4() {
    final provider = _wifiIpv4Provider;
    return provider != null ? provider() : _networkInfo.getWifiIP();
  }

  Future<String?> _getWifiIpv6() {
    final provider = _wifiIpv6Provider;
    return provider != null ? provider() : _networkInfo.getWifiIPv6();
  }

  Future<String?> _getWifiSubmask() {
    final provider = _wifiSubmaskProvider;
    return provider != null ? provider() : _networkInfo.getWifiSubmask();
  }

  Future<ProcessResult> _runProcess(String executable, List<String> arguments) {
    final runner = _processRunner;
    return runner != null
        ? runner(executable, arguments)
        : Process.run(executable, arguments);
  }

  _LanIpVersionPreference _parseIpVersionPreference(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'ipv4':
        return _LanIpVersionPreference.ipv4;
      case 'ipv6':
        return _LanIpVersionPreference.ipv6;
      default:
        return _LanIpVersionPreference.auto;
    }
  }

  String _defaultNoTargetMessage(_LanIpVersionPreference versionPreference) {
    final base = switch (versionPreference) {
      _LanIpVersionPreference.ipv4 =>
        'Could not determine the local IPv4 subnet.',
      _LanIpVersionPreference.ipv6 =>
        'Could not determine any local IPv6 neighbors to scan.',
      _LanIpVersionPreference.auto =>
        'Could not determine the local network to scan.',
    };

    return '$base Provide a subnet parameter (for example 192.168.1.0/24 or '
        'fd00::/120) or ensure the device is connected to WiFi.';
  }

  static int _subnetMaskToPrefix(String mask) {
    final parts = mask.split('.');
    if (parts.length != 4) {
      return 24;
    }

    var bits = 0;
    for (final part in parts) {
      final octet = int.tryParse(part) ?? 0;
      var value = octet;
      while (value > 0) {
        bits += value & 1;
        value >>= 1;
      }
    }
    return bits.clamp(8, 30);
  }

  bool _shouldIncludeDiscoveredIpv6Address(String ip) {
    return LanIpNetwork.looksLikeIpv6(ip) &&
        !_isLoopbackIp(ip) &&
        !_isMulticastIpv6(ip);
  }

  bool _isLoopbackIp(String value) {
    final address = InternetAddress.tryParse(LanIpNetwork.stripScopeId(value));
    return address?.isLoopback ?? false;
  }

  bool _isLinkLocalIpv6(String value) {
    final address = InternetAddress.tryParse(LanIpNetwork.stripScopeId(value));
    if (address == null || address.type != InternetAddressType.IPv6) {
      return false;
    }

    final bytes = address.rawAddress;
    return bytes.isNotEmpty && bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
  }

  bool _isMulticastIpv6(String value) {
    final address = InternetAddress.tryParse(LanIpNetwork.stripScopeId(value));
    if (address == null || address.type != InternetAddressType.IPv6) {
      return false;
    }
    return address.rawAddress.isNotEmpty && address.rawAddress.first == 0xff;
  }

  String _withScopeIfNeeded(String ip, String interfaceName) {
    if (!_isLinkLocalIpv6(ip) || interfaceName.isEmpty || ip.contains('%')) {
      return ip;
    }
    return '$ip%$interfaceName';
  }

  String? _buildReversePointerName(String ip) {
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
}

class _ScanPlan {
  const _ScanPlan({
    required this.candidateIps,
    required this.summaryLabel,
    required this.hostCount,
    required this.addressFamilies,
    required this.strategy,
  });

  final List<String> candidateIps;
  final String summaryLabel;
  final int hostCount;
  final List<String> addressFamilies;
  final String strategy;
}

class _ScanPlanResult {
  const _ScanPlanResult.success(this.plan) : errorMessage = null;
  const _ScanPlanResult.error(this.errorMessage) : plan = null;

  final _ScanPlan? plan;
  final String? errorMessage;
}

final lanScanServiceProvider = Provider<LanScanService>((ref) {
  final service = LanScanService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
