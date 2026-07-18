import 'dart:convert';
import 'dart:io';

import 'network_address_utils.dart';

typedef NetworkNeighborProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

enum NetworkNeighborPlatform { macOs, linux, unsupported }

NetworkNeighborPlatform _currentPlatform() {
  if (Platform.isMacOS) return NetworkNeighborPlatform.macOs;
  if (Platform.isLinux) return NetworkNeighborPlatform.linux;
  return NetworkNeighborPlatform.unsupported;
}

class NetworkNeighborTools {
  NetworkNeighborTools({NetworkNeighborPlatform? platform})
    : _platform = platform ?? _currentPlatform();

  static const Set<String> _supportedVersions = {'all', 'ipv4', 'ipv6'};
  final NetworkNeighborPlatform _platform;

  Future<String> arp({
    String? host,
    String ipVersion = 'all',
    NetworkNeighborProcessRunner? processRunner,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedVersions.join(', ')}',
      });
    }

    if (_platform == NetworkNeighborPlatform.unsupported) {
      return jsonEncode({
        'error': true,
        'message':
            'ARP inspection is only supported on macOS and Linux. '
            'This platform does not expose a compatible local neighbor table.',
      });
    }

    final requestedHost = host?.trim();
    final entries = <_NeighborCacheEntry>[];

    if (normalizedVersion != 'ipv6') {
      entries.addAll(
        _platform == NetworkNeighborPlatform.macOs
            ? await _readMacOsArpTable(processRunner: processRunner)
            : await _readLinuxNeighborTable(
                ipv6: false,
                processRunner: processRunner,
              ),
      );
    }

    if (normalizedVersion != 'ipv4') {
      entries.addAll(
        _platform == NetworkNeighborPlatform.macOs
            ? await _readMacOsNdpTable(processRunner: processRunner)
            : await _readLinuxNeighborTable(
                ipv6: true,
                processRunner: processRunner,
              ),
      );
    }

    final matchedEntries = requestedHost == null || requestedHost.isEmpty
        ? entries
        : entries.where(
            (entry) => _matchesNeighborFilter(entry, requestedHost),
          );
    final filteredEntries = matchedEntries.toList(growable: false)
      ..sort((a, b) => compareNetworkIpAddresses(a.ip, b.ip));

    return jsonEncode({
      'host': requestedHost,
      'ip_version': normalizedVersion,
      'entries_found': filteredEntries.length,
      'entries': filteredEntries.map((entry) => entry.toJson()).toList(),
    });
  }

  Future<String> ndp({
    String? host,
    NetworkNeighborProcessRunner? processRunner,
  }) {
    return arp(host: host, ipVersion: 'ipv6', processRunner: processRunner);
  }

  Future<List<_NeighborCacheEntry>> _readMacOsArpTable({
    NetworkNeighborProcessRunner? processRunner,
  }) async {
    final result = await _runProcess('arp', const [
      '-a',
    ], processRunner: processRunner);
    if (result.exitCode != 0) return const [];

    final entries = <_NeighborCacheEntry>[];
    final regex = RegExp(
      r'^(\S+)\s+\((\d+\.\d+\.\d+\.\d+)\)\s+at\s+([0-9a-fA-F:]+|\(incomplete\))(?:\s+on\s+(\S+))?',
    );

    for (final line in (result.stdout as String).split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match == null) continue;

      final hostname = match.group(1);
      final mac = match.group(3);
      if (mac == null || mac == '(incomplete)' || mac == 'ff:ff:ff:ff:ff:ff') {
        continue;
      }

      entries.add(
        _NeighborCacheEntry(
          ip: match.group(2)!,
          ipVersion: 'ipv4',
          mac: mac.toLowerCase(),
          hostname: hostname == null || hostname == '?' ? null : hostname,
          interfaceName: match.group(4),
          source: 'arp',
        ),
      );
    }

    return entries;
  }

  Future<List<_NeighborCacheEntry>> _readMacOsNdpTable({
    NetworkNeighborProcessRunner? processRunner,
  }) async {
    final result = await _runProcess('ndp', const [
      '-an',
    ], processRunner: processRunner);
    if (result.exitCode != 0) return const [];

    final entries = <_NeighborCacheEntry>[];
    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Neighbor ')) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 3) continue;

      final mac = parts[1];
      if (mac == '(incomplete)' || mac == 'ff:ff:ff:ff:ff:ff') continue;

      entries.add(
        _NeighborCacheEntry(
          ip: parts[0],
          ipVersion: 'ipv6',
          mac: mac.toLowerCase(),
          interfaceName: parts[2],
          state: parts.length >= 5 ? parts.last : null,
          source: 'ndp',
        ),
      );
    }

    return entries;
  }

  Future<List<_NeighborCacheEntry>> _readLinuxNeighborTable({
    required bool ipv6,
    NetworkNeighborProcessRunner? processRunner,
  }) async {
    final arguments = ipv6
        ? const ['-6', 'neighbor', 'show']
        : const ['neighbor', 'show'];
    final result = await _runProcess(
      'ip',
      arguments,
      processRunner: processRunner,
    );
    if (result.exitCode != 0) return const [];

    final entries = <_NeighborCacheEntry>[];
    final regex = RegExp(
      r'^([0-9a-fA-F:.%]+)\s+dev\s+(\S+)(?:\s+lladdr\s+([0-9a-fA-F:]+))?(?:\s+router)?(?:\s+(\S+))?$',
    );

    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.contains('FAILED') ||
          trimmed.contains('INCOMPLETE')) {
        continue;
      }

      final match = regex.firstMatch(trimmed);
      if (match == null) continue;

      final mac = match.group(3);
      if (mac == null || mac == 'ff:ff:ff:ff:ff:ff') continue;

      entries.add(
        _NeighborCacheEntry(
          ip: match.group(1)!,
          ipVersion: ipv6 ? 'ipv6' : 'ipv4',
          mac: mac.toLowerCase(),
          interfaceName: match.group(2),
          state: match.group(4),
          source: ipv6 ? 'ndp' : 'arp',
        ),
      );
    }

    return entries;
  }

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    NetworkNeighborProcessRunner? processRunner,
  }) {
    final runner = processRunner;
    return runner != null
        ? runner(executable, arguments)
        : Process.run(executable, arguments);
  }

  bool _matchesNeighborFilter(_NeighborCacheEntry entry, String requestedHost) {
    final normalizedFilter = requestedHost.trim().toLowerCase();
    if (normalizedFilter.isEmpty) return true;

    final filterIp = normalizeNetworkIpForComparison(normalizedFilter);
    if (normalizeNetworkIpForComparison(entry.ip) == filterIp) return true;

    final hostname = entry.hostname?.toLowerCase();
    return hostname != null && hostname.contains(normalizedFilter);
  }
}

class _NeighborCacheEntry {
  const _NeighborCacheEntry({
    required this.ip,
    required this.ipVersion,
    required this.source,
    this.mac,
    this.hostname,
    this.interfaceName,
    this.state,
  });

  final String ip;
  final String ipVersion;
  final String source;
  final String? mac;
  final String? hostname;
  final String? interfaceName;
  final String? state;

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'ip_version': ipVersion,
    'source': source,
    if (mac != null) 'mac': mac,
    if (hostname != null) 'hostname': hostname,
    if (interfaceName != null) 'interface': interfaceName,
    if (state != null) 'state': state,
  };
}
