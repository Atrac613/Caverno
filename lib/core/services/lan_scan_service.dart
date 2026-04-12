import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_ping/dart_ping.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../utils/logger.dart';

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
    if (hostname != null) 'hostname': hostname,
    if (mac != null) 'mac': mac,
    if (vendor != null) 'vendor': vendor,
    if (responseTimeMs != null) 'response_time_ms': responseTimeMs,
    if (openPorts.isNotEmpty) 'open_ports': openPorts,
  };
}

/// Manages LAN scanning: ping sweep, port probing, reverse DNS, and ARP.
class LanScanService {
  final NetworkInfo _networkInfo = NetworkInfo();

  List<LanHost> _scanResults = [];

  /// Maximum hosts to ping concurrently to avoid socket exhaustion.
  static const int _concurrencyLimit = 50;

  /// Default ports to probe on each discovered host.
  static const List<int> _defaultPorts = [22, 80, 443, 8080];

  /// Trigger a LAN scan and return the results as a JSON string.
  Future<String> startScan({
    String? subnet,
    int timeoutMs = 1000,
    List<int>? ports,
  }) async {
    final effectiveTimeout = timeoutMs.clamp(100, 5000);
    final effectivePorts = _clampPorts(ports ?? _defaultPorts);

    // Resolve the subnet to scan.
    final subnetRange = await _resolveSubnet(subnet);
    if (subnetRange == null) {
      return jsonEncode({
        'error': true,
        'message': 'Could not determine the local subnet. '
            'Provide a subnet parameter (e.g. 192.168.1.0/24) or '
            'ensure the device is connected to WiFi.',
      });
    }

    appLog(
      '[LanScanService] Starting scan: ${subnetRange.baseIp}/${subnetRange.prefix} '
      '(${subnetRange.hostCount} hosts, timeout=${effectiveTimeout}ms, '
      'ports=$effectivePorts)',
    );

    // Fetch ARP table once before scanning for MAC resolution.
    final arpTable = await _fetchArpTable();

    // Ping sweep with concurrency limit.
    final allIps = subnetRange.allHostIps();
    final discovered = <LanHost>[];

    for (var i = 0; i < allIps.length; i += _concurrencyLimit) {
      final batch = allIps.sublist(
        i,
        (i + _concurrencyLimit).clamp(0, allIps.length),
      );
      final results = await Future.wait(
        batch.map(
          (ip) => _probeHost(
            ip: ip,
            timeoutMs: effectiveTimeout,
            ports: effectivePorts,
            arpTable: arpTable,
          ),
        ),
      );
      for (final host in results) {
        if (host != null) {
          discovered.add(host);
        }
      }
    }

    // Sort by IP numerically by default.
    discovered.sort((a, b) => _compareIps(a.ip, b.ip));
    _scanResults = discovered;

    appLog('[LanScanService] Scan complete: ${discovered.length} hosts found');

    return jsonEncode({
      'subnet': '${subnetRange.baseIp}/${subnetRange.prefix}',
      'hosts_scanned': subnetRange.hostCount,
      'hosts_found': discovered.length,
      'hosts': discovered.map((h) => h.toJson()).toList(),
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
        sorted.sort((a, b) => _compareIps(a.ip, b.ip));
    }

    return jsonEncode({
      'hosts_found': sorted.length,
      'hosts': sorted.map((h) => h.toJson()).toList(),
    });
  }

  Future<void> dispose() async {
    _scanResults.clear();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Probe a single host: ping → port scan → hostname resolution.
  Future<LanHost?> _probeHost({
    required String ip,
    required int timeoutMs,
    required List<int> ports,
    required Map<String, _ArpEntry> arpTable,
  }) async {
    final timeoutSec = (timeoutMs / 1000).ceil().clamp(1, 10);

    // Try ping first.
    double? rttMs;
    bool alive = false;

    try {
      final ping = Ping(ip, count: 1, timeout: timeoutSec);
      await for (final event in ping.stream) {
        if (event.response != null && event.response!.time != null) {
          rttMs = event.response!.time!.inMicroseconds / 1000.0;
          alive = true;
        }
        break;
      }
    } catch (_) {
      // Ping failed — try TCP fallback below.
    }

    // If ping didn't work, try a quick TCP connect to common ports as fallback.
    if (!alive) {
      final tcpResult = await _quickTcpProbe(
        ip: ip,
        ports: ports.isEmpty ? [80, 443] : [ports.first],
        timeoutMs: timeoutMs,
      );
      if (tcpResult != null) {
        alive = true;
        rttMs = tcpResult;
      }
    }

    if (!alive) return null;

    // Port scan on alive host.
    final openPorts = await _scanPorts(
      ip: ip,
      ports: ports,
      timeoutMs: timeoutMs,
    );

    // Hostname resolution priority chain:
    // 1. Reverse DNS (fast, OS-cached)
    // 2. ARP table hostname (already fetched, no extra I/O)
    // 3. mDNS reverse lookup (only if still unresolved)
    String? hostname;
    try {
      final results = await InternetAddress(ip).reverse();
      if (results.host != ip) {
        hostname = results.host;
      }
    } catch (_) {
      // Reverse DNS not available for this IP.
    }

    final arpEntry = arpTable[ip];
    final mac = arpEntry?.mac;

    // Fallback: ARP table hostname.
    if (hostname == null && arpEntry?.hostname != null) {
      hostname = arpEntry!.hostname;
    }

    // Fallback: mDNS reverse lookup.
    hostname ??= await _mdnsReverseLookup(ip, timeoutMs: timeoutMs);

    return LanHost(
      ip: ip,
      hostname: hostname,
      mac: mac,
      responseTimeMs: rttMs != null
          ? double.parse(rttMs.toStringAsFixed(2))
          : null,
      openPorts: openPorts,
    );
  }

  /// Attempt a quick TCP connect to detect hosts that block ICMP.
  Future<double?> _quickTcpProbe({
    required String ip,
    required List<int> ports,
    required int timeoutMs,
  }) async {
    for (final port in ports) {
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(
          ip,
          port,
          timeout: Duration(milliseconds: timeoutMs),
        );
        sw.stop();
        socket.destroy();
        return sw.elapsedMicroseconds / 1000.0;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Scan specified ports on a host.
  Future<List<int>> _scanPorts({
    required String ip,
    required List<int> ports,
    required int timeoutMs,
  }) async {
    if (ports.isEmpty) return [];

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

    return results.where((p) => p > 0).toList()..sort();
  }

  /// Resolve the target subnet from the user parameter or auto-detect.
  Future<_SubnetRange?> _resolveSubnet(String? userSubnet) async {
    if (userSubnet != null && userSubnet.isNotEmpty) {
      return _SubnetRange.parse(userSubnet);
    }

    // Auto-detect from WiFi IP and subnet mask.
    try {
      final ip = await _networkInfo.getWifiIP();
      final mask = await _networkInfo.getWifiSubmask();

      if (ip == null || ip.isEmpty) return null;

      final prefix = mask != null && mask.isNotEmpty
          ? _subnetMaskToPrefix(mask)
          : 24; // Default to /24 if mask unavailable.

      return _SubnetRange.fromIpAndPrefix(ip, prefix);
    } catch (e) {
      appLog('[LanScanService] Failed to detect subnet: $e');
      return null;
    }
  }

  /// Fetch the system ARP table (macOS/Linux) and return IP → ARP entry mapping.
  Future<Map<String, _ArpEntry>> _fetchArpTable() async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return {};
    }

    try {
      final result = await Process.run('arp', ['-a']);
      if (result.exitCode != 0) return {};

      final table = <String, _ArpEntry>{};
      final lines = (result.stdout as String).split('\n');

      // macOS format: hostname (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ...
      // Linux format: hostname (192.168.1.1) at aa:bb:cc:dd:ee:ff [ether] ...
      final regex = RegExp(
        r'(\S+)\s+\((\d+\.\d+\.\d+\.\d+)\)\s+at\s+([0-9a-fA-F:]+)',
      );

      for (final line in lines) {
        final match = regex.firstMatch(line);
        if (match != null) {
          final rawHostname = match.group(1)!;
          final ip = match.group(2)!;
          final mac = match.group(3)!;
          if (mac != '(incomplete)' && mac != 'ff:ff:ff:ff:ff:ff') {
            // macOS uses '?' when hostname is unknown.
            final hostname =
                (rawHostname != '?' && rawHostname != ip) ? rawHostname : null;
            table[ip] = _ArpEntry(
              mac: mac.toLowerCase(),
              hostname: hostname,
            );
          }
        }
      }

      appLog('[LanScanService] ARP table: ${table.length} entries');
      return table;
    } catch (e) {
      appLog('[LanScanService] ARP table fetch failed: $e');
      return {};
    }
  }

  /// Attempt mDNS reverse lookup for the given IP.
  /// Returns the mDNS hostname or null if not resolvable.
  Future<String?> _mdnsReverseLookup(String ip, {int timeoutMs = 2000}) async {
    // Build the PTR name: e.g. 192.168.1.42 → 42.1.168.192.in-addr.arpa
    final parts = ip.split('.').reversed.join('.');
    final ptrName = '$parts.in-addr.arpa';

    MDnsClient? client;
    try {
      client = MDnsClient();
      await client.start();

      String? resolved;
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(ptrName),
      )) {
        resolved = ptr.domainName;
        break; // Take the first result.
      }

      return resolved;
    } catch (_) {
      return null;
    } finally {
      client?.stop();
    }
  }

  /// Clamp the ports list to a maximum of 20 entries.
  List<int> _clampPorts(List<int> ports) {
    final clamped = ports
        .where((p) => p > 0 && p <= 65535)
        .take(20)
        .toList();
    return clamped;
  }

  /// Convert a subnet mask string (e.g. 255.255.255.0) to prefix length.
  static int _subnetMaskToPrefix(String mask) {
    final parts = mask.split('.');
    if (parts.length != 4) return 24;

    var bits = 0;
    for (final part in parts) {
      final octet = int.tryParse(part) ?? 0;
      // Count set bits in each octet.
      var value = octet;
      while (value > 0) {
        bits += value & 1;
        value >>= 1;
      }
    }
    return bits.clamp(8, 30);
  }

  /// Compare two IP addresses numerically.
  static int _compareIps(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 4; i++) {
      final diff = aParts[i] - bParts[i];
      if (diff != 0) return diff;
    }
    return 0;
  }
}

/// ARP table entry with MAC address and optional hostname.
class _ArpEntry {
  const _ArpEntry({this.mac, this.hostname});

  final String? mac;
  final String? hostname;
}

/// Represents a range of IPs within a subnet.
class _SubnetRange {
  const _SubnetRange({
    required this.baseIp,
    required this.prefix,
    required this.networkAddress,
    required this.broadcastAddress,
  });

  final String baseIp;
  final int prefix;
  final int networkAddress;
  final int broadcastAddress;

  /// Number of usable host addresses (excluding network and broadcast).
  int get hostCount {
    final total = broadcastAddress - networkAddress - 1;
    return total.clamp(0, 1024); // Cap at /22 to avoid huge scans.
  }

  /// Generate all host IP addresses in the range.
  List<String> allHostIps() {
    final ips = <String>[];
    // Skip network address (+1) and broadcast address.
    for (var addr = networkAddress + 1; addr < broadcastAddress; addr++) {
      if (ips.length >= 1024) break; // Safety cap.
      ips.add(_intToIp(addr));
    }
    return ips;
  }

  /// Parse a CIDR notation string like "192.168.1.0/24".
  static _SubnetRange? parse(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;

    final ip = parts[0];
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 8 || prefix > 30) return null;

    return fromIpAndPrefix(ip, prefix);
  }

  /// Build a subnet range from an IP address and prefix length.
  static _SubnetRange? fromIpAndPrefix(String ip, int prefix) {
    final ipInt = _ipToInt(ip);
    if (ipInt == null) return null;

    final mask = _prefixToMask(prefix);
    final network = ipInt & mask;
    final broadcast = network | (~mask & 0xFFFFFFFF);

    return _SubnetRange(
      baseIp: _intToIp(network),
      prefix: prefix,
      networkAddress: network,
      broadcastAddress: broadcast,
    );
  }

  static int? _ipToInt(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    var result = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return null;
      result = (result << 8) | octet;
    }
    return result;
  }

  static String _intToIp(int value) {
    return '${(value >> 24) & 0xFF}.'
        '${(value >> 16) & 0xFF}.'
        '${(value >> 8) & 0xFF}.'
        '${value & 0xFF}';
  }

  static int _prefixToMask(int prefix) {
    return prefix == 0 ? 0 : (~0 << (32 - prefix)) & 0xFFFFFFFF;
  }
}

final lanScanServiceProvider = Provider<LanScanService>((ref) {
  final service = LanScanService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
