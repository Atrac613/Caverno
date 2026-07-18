import 'dart:convert';
import 'dart:io';

import 'network_address_utils.dart';
import 'network_tool_dependencies.dart';

enum NetworkRoutePlatform {
  macos,
  linux,
  unsupported;

  static NetworkRoutePlatform get current {
    if (Platform.isMacOS) {
      return NetworkRoutePlatform.macos;
    }
    if (Platform.isLinux) {
      return NetworkRoutePlatform.linux;
    }
    return NetworkRoutePlatform.unsupported;
  }
}

/// Route, interface, and path-MTU diagnostics behind injectable platform IO.
class NetworkRouteTools {
  NetworkRouteTools({NetworkRoutePlatform? platform})
    : _platform = platform ?? NetworkRoutePlatform.current;

  static const Set<String> _supportedInterfaceVersions = {
    'all',
    'ipv4',
    'ipv6',
  };
  static const Set<String> _supportedRouteVersions = {'auto', 'ipv4', 'ipv6'};

  final NetworkRoutePlatform _platform;

  Future<String> routeLookup({
    required String host,
    String ipVersion = 'auto',
    NetworkProcessRunner? processRunner,
    NetworkAddressLookup? addressLookup,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedRouteVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedRouteVersions.join(', ')}',
      });
    }

    if (_platform == NetworkRoutePlatform.unsupported) {
      return jsonEncode({
        'error': true,
        'message': 'Route inspection is only supported on macOS and Linux.',
      });
    }

    final targets = await _resolveRouteTargets(
      host,
      requestedVersion: normalizedVersion,
      addressLookup: addressLookup,
    );

    final routes = <_RouteLookupEntry>[];
    for (final target in targets) {
      final entry = _platform == NetworkRoutePlatform.macos
          ? await _lookupMacOsRoute(target, processRunner: processRunner)
          : await _lookupLinuxRoute(target, processRunner: processRunner);
      if (entry != null) {
        routes.add(entry);
      }
    }

    return jsonEncode({
      'host': host,
      'ip_version': normalizedVersion,
      'routes_found': routes.length,
      'routes': routes.map((entry) => entry.toJson()).toList(),
    });
  }

  Future<String> interfaceInfo({
    String? interfaceName,
    String ipVersion = 'all',
    NetworkProcessRunner? processRunner,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedInterfaceVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: '
            '${_supportedInterfaceVersions.join(', ')}',
      });
    }

    final requestedInterface = interfaceName?.trim();
    final interfaces = await _loadInterfaceInfoEntries(
      processRunner: processRunner,
    );
    final filtered = interfaces
        .where(
          (entry) =>
              requestedInterface == null ||
              requestedInterface.isEmpty ||
              entry.name == requestedInterface,
        )
        .map((entry) => entry.filtered(ipVersion: normalizedVersion))
        .where(
          (entry) =>
              normalizedVersion == 'all' ||
              entry.addresses.isNotEmpty ||
              entry.defaultGateways.isNotEmpty,
        )
        .toList(growable: false);

    return jsonEncode({
      'interface': requestedInterface,
      'ip_version': normalizedVersion,
      'interfaces_found': filtered.length,
      'interfaces': filtered.map((entry) => entry.toJson()).toList(),
    });
  }

  Future<String> pathMtu({
    required String host,
    String ipVersion = 'auto',
    NetworkProcessRunner? processRunner,
    NetworkAddressLookup? addressLookup,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedRouteVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedRouteVersions.join(', ')}',
      });
    }

    if (_platform == NetworkRoutePlatform.unsupported) {
      return jsonEncode({
        'error': true,
        'message': 'Path MTU discovery is only supported on macOS and Linux.',
      });
    }

    final targets = await _resolveRouteTargets(
      host,
      requestedVersion: normalizedVersion,
      addressLookup: addressLookup,
    );
    final measurements = <_PathMtuMeasurement>[];
    final interfaces = await _loadInterfaceInfoEntries(
      processRunner: processRunner,
    );

    for (final target in targets) {
      final route = _platform == NetworkRoutePlatform.macos
          ? await _lookupMacOsRoute(target, processRunner: processRunner)
          : await _lookupLinuxRoute(target, processRunner: processRunner);
      final measurement = _platform == NetworkRoutePlatform.linux
          ? await _runLinuxTracepath(
              target,
              route: route,
              interfaces: interfaces,
              processRunner: processRunner,
            )
          : _buildInterfaceMtuFallbackMeasurement(
              target,
              route: route,
              interfaces: interfaces,
              note:
                  'macOS fallback returns the egress interface MTU as a local '
                  'upper bound when tracepath is unavailable.',
            );
      if (measurement != null) {
        measurements.add(measurement);
      }
    }

    return jsonEncode({
      'host': host,
      'ip_version': normalizedVersion,
      'measurements_found': measurements.length,
      'measurements': measurements.map((entry) => entry.toJson()).toList(),
    });
  }

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    NetworkProcessRunner? processRunner,
  }) {
    final runner = processRunner;
    return runner != null
        ? runner(executable, arguments)
        : Process.run(executable, arguments);
  }

  Future<List<_ResolvedRouteTarget>> _resolveRouteTargets(
    String host, {
    required String requestedVersion,
    NetworkAddressLookup? addressLookup,
  }) async {
    final literal = InternetAddress.tryParse(
      normalizeNetworkIpForComparison(host),
    );
    if (literal != null) {
      final literalVersion = literal.type == InternetAddressType.IPv4
          ? 'ipv4'
          : 'ipv6';
      if (requestedVersion != 'auto' && literalVersion != requestedVersion) {
        return const [];
      }
      return [
        _ResolvedRouteTarget(
          requestedHost: host,
          commandTarget: host,
          resolvedIp: host,
          ipVersion: literalVersion,
        ),
      ];
    }

    final lookup = addressLookup ?? InternetAddress.lookup;
    final targets = <_ResolvedRouteTarget>[];
    final seenVersions = <String>{};

    Future<void> addLookupTargets(InternetAddressType type) async {
      final addresses = await lookup(host, type: type);
      for (final address in addresses) {
        final version = address.type == InternetAddressType.IPv4
            ? 'ipv4'
            : 'ipv6';
        if (requestedVersion == 'auto' && !seenVersions.add(version)) {
          continue;
        }
        targets.add(
          _ResolvedRouteTarget(
            requestedHost: host,
            commandTarget: address.address,
            resolvedIp: address.address,
            ipVersion: version,
          ),
        );
      }
    }

    if (requestedVersion == 'auto') {
      try {
        await addLookupTargets(InternetAddressType.IPv4);
      } on SocketException {
        // Continue so IPv6-only hosts can still return a usable route.
      }
      try {
        await addLookupTargets(InternetAddressType.IPv6);
      } on SocketException {
        // Continue so IPv4-only hosts can still return a usable route.
      }
    } else {
      await addLookupTargets(
        requestedVersion == 'ipv4'
            ? InternetAddressType.IPv4
            : InternetAddressType.IPv6,
      );
    }

    return targets;
  }

  Future<_RouteLookupEntry?> _lookupMacOsRoute(
    _ResolvedRouteTarget target, {
    NetworkProcessRunner? processRunner,
  }) async {
    final arguments = target.ipVersion == 'ipv6'
        ? ['-n', 'get', '-inet6', target.commandTarget]
        : ['-n', 'get', target.commandTarget];
    final result = await _runProcess(
      'route',
      arguments,
      processRunner: processRunner,
    );
    if (result.exitCode != 0) {
      return null;
    }

    final fields = <String, String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        fields[key] = value;
      }
    }

    return _RouteLookupEntry(
      requestedHost: target.requestedHost,
      resolvedIp: target.resolvedIp,
      ipVersion: target.ipVersion,
      destination: fields['destination'] ?? fields['route to'],
      gateway: fields['gateway'],
      interfaceName: fields['interface'],
      sourceIp:
          fields['if address'] ?? fields['source address'] ?? fields['source'],
      flags: fields['flags'],
      rawOutput: (result.stdout as String).trim(),
    );
  }

  Future<_RouteLookupEntry?> _lookupLinuxRoute(
    _ResolvedRouteTarget target, {
    NetworkProcessRunner? processRunner,
  }) async {
    final arguments = target.ipVersion == 'ipv6'
        ? ['-6', 'route', 'get', target.commandTarget]
        : ['route', 'get', target.commandTarget];
    final result = await _runProcess(
      'ip',
      arguments,
      processRunner: processRunner,
    );
    if (result.exitCode != 0) {
      return null;
    }

    final lines = (result.stdout as String)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return null;
    }

    final tokens = lines.first.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty) {
      return null;
    }

    var index = 0;
    String? routeType;
    String? destination;
    if (_linuxSpecialRouteTypes.contains(tokens.first) && tokens.length >= 2) {
      routeType = tokens.first;
      destination = tokens[1];
      index = 2;
    } else {
      destination = tokens.first;
      index = 1;
    }

    String? gateway;
    String? interfaceName;
    String? sourceIp;
    String? flags;

    while (index < tokens.length) {
      final token = tokens[index];
      switch (token) {
        case 'via':
          if (index + 1 < tokens.length) {
            gateway = tokens[index + 1];
          }
          index += 2;
          break;
        case 'dev':
          if (index + 1 < tokens.length) {
            interfaceName = tokens[index + 1];
          }
          index += 2;
          break;
        case 'src':
          if (index + 1 < tokens.length) {
            sourceIp = tokens[index + 1];
          }
          index += 2;
          break;
        case 'metric':
        case 'proto':
        case 'scope':
        case 'pref':
        case 'table':
        case 'uid':
        case 'from':
          index += index + 1 < tokens.length ? 2 : 1;
          break;
        default:
          index += 1;
          break;
      }
    }

    if (routeType != null) {
      flags = routeType;
    }

    return _RouteLookupEntry(
      requestedHost: target.requestedHost,
      resolvedIp: target.resolvedIp,
      ipVersion: target.ipVersion,
      destination: destination,
      gateway: gateway,
      interfaceName: interfaceName,
      sourceIp: sourceIp,
      flags: flags,
      rawOutput: (result.stdout as String).trim(),
    );
  }

  Future<List<_InterfaceInfoEntry>> _loadInterfaceInfoEntries({
    NetworkProcessRunner? processRunner,
  }) async {
    if (_platform == NetworkRoutePlatform.macos) {
      final interfaces = await _readMacOsInterfaceInfo(
        processRunner: processRunner,
      );
      if (interfaces.isNotEmpty) {
        return interfaces;
      }
    }

    if (_platform == NetworkRoutePlatform.linux) {
      final interfaces = await _readLinuxInterfaceInfo(
        processRunner: processRunner,
      );
      if (interfaces.isNotEmpty) {
        return interfaces;
      }
    }

    final networkInterfaces = await NetworkInterface.list(
      includeLinkLocal: true,
      includeLoopback: true,
    );
    return networkInterfaces
        .map(
          (interface) => _InterfaceInfoEntry(
            name: interface.name,
            addresses: interface.addresses
                .map(
                  (address) => _InterfaceAddressInfo(
                    address: address.address,
                    ipVersion: address.type == InternetAddressType.IPv4
                        ? 'ipv4'
                        : 'ipv6',
                    scope: _addressScope(address.address),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  Future<List<_InterfaceInfoEntry>> _readMacOsInterfaceInfo({
    NetworkProcessRunner? processRunner,
  }) async {
    final result = await _runProcess(
      'ifconfig',
      const [],
      processRunner: processRunner,
    );
    if (result.exitCode != 0) {
      return const [];
    }

    final gateways = await _readMacOsDefaultGateways(
      processRunner: processRunner,
    );
    final builders = <String, _InterfaceInfoEntryBuilder>{};
    _InterfaceInfoEntryBuilder? current;

    for (final line in (result.stdout as String).split('\n')) {
      final headerMatch = RegExp(
        r'^([0-9A-Za-z._:-]+):\s+flags=\d+<([^>]*)>(?:\s+mtu\s+(\d+))?',
      ).firstMatch(line);
      if (headerMatch != null) {
        final name = headerMatch.group(1)!;
        current = builders.putIfAbsent(
          name,
          () => _InterfaceInfoEntryBuilder(name),
        );
        current
          ..flags = headerMatch.group(2)?.split(',') ?? const []
          ..mtu = int.tryParse(headerMatch.group(3) ?? '')
          ..defaultGateways = gateways[name] ?? const [];
        continue;
      }

      if (current == null) {
        continue;
      }

      final trimmed = line.trim();
      if (trimmed.startsWith('ether ')) {
        current.mac = trimmed.substring('ether '.length).trim().toLowerCase();
        continue;
      }
      if (trimmed.startsWith('status: ')) {
        current.status = trimmed.substring('status: '.length).trim();
        continue;
      }

      final ipv4Match = RegExp(
        r'^inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+(\S+)',
      ).firstMatch(trimmed);
      if (ipv4Match != null) {
        current.addresses.add(
          _InterfaceAddressInfo(
            address: ipv4Match.group(1)!,
            ipVersion: 'ipv4',
            prefixLength: _ipv4MaskToPrefix(ipv4Match.group(2)!),
            scope: 'global',
          ),
        );
        continue;
      }

      final ipv6Match = RegExp(
        r'^inet6\s+([0-9a-fA-F:.%]+)\s+prefixlen\s+(\d+)',
      ).firstMatch(trimmed);
      if (ipv6Match != null) {
        final address = ipv6Match.group(1)!;
        current.addresses.add(
          _InterfaceAddressInfo(
            address: address,
            ipVersion: 'ipv6',
            prefixLength: int.tryParse(ipv6Match.group(2)!),
            scope: _addressScope(address),
          ),
        );
      }
    }

    return builders.values
        .map((builder) => builder.build())
        .toList(growable: false);
  }

  Future<List<_InterfaceInfoEntry>> _readLinuxInterfaceInfo({
    NetworkProcessRunner? processRunner,
  }) async {
    final result = await _runProcess('ip', const [
      'addr',
      'show',
    ], processRunner: processRunner);
    if (result.exitCode != 0) {
      return const [];
    }

    final gateways = await _readLinuxDefaultGateways(
      processRunner: processRunner,
    );
    final builders = <String, _InterfaceInfoEntryBuilder>{};
    _InterfaceInfoEntryBuilder? current;

    for (final line in (result.stdout as String).split('\n')) {
      final headerMatch = RegExp(
        r'^\d+:\s+([^:]+):\s+<([^>]*)>.*\bmtu\s+(\d+)(?:.*\bstate\s+(\S+))?',
      ).firstMatch(line);
      if (headerMatch != null) {
        final name = headerMatch.group(1)!.split('@').first;
        current = builders.putIfAbsent(
          name,
          () => _InterfaceInfoEntryBuilder(name),
        );
        current
          ..flags = headerMatch.group(2)?.split(',') ?? const []
          ..mtu = int.tryParse(headerMatch.group(3) ?? '')
          ..status = headerMatch.group(4)
          ..defaultGateways = gateways[name] ?? const [];
        continue;
      }

      if (current == null) {
        continue;
      }

      final linkMatch = RegExp(
        r'^\s+link/\S+\s+([0-9a-fA-F:]{17})',
      ).firstMatch(line);
      if (linkMatch != null) {
        current.mac = linkMatch.group(1)?.toLowerCase();
        continue;
      }

      final ipv4Match = RegExp(
        r'^\s+inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)(?:\s+brd\s+\S+)?\s+scope\s+(\S+)',
      ).firstMatch(line);
      if (ipv4Match != null) {
        current.addresses.add(
          _InterfaceAddressInfo(
            address: ipv4Match.group(1)!,
            ipVersion: 'ipv4',
            prefixLength: int.tryParse(ipv4Match.group(2)!),
            scope: ipv4Match.group(3)!,
          ),
        );
        continue;
      }

      final ipv6Match = RegExp(
        r'^\s+inet6\s+([0-9a-fA-F:.%]+)/(\d+)\s+scope\s+(\S+)',
      ).firstMatch(line);
      if (ipv6Match != null) {
        current.addresses.add(
          _InterfaceAddressInfo(
            address: ipv6Match.group(1)!,
            ipVersion: 'ipv6',
            prefixLength: int.tryParse(ipv6Match.group(2)!),
            scope: ipv6Match.group(3)!,
          ),
        );
      }
    }

    return builders.values
        .map((builder) => builder.build())
        .toList(growable: false);
  }

  Future<Map<String, List<_InterfaceGateway>>> _readMacOsDefaultGateways({
    NetworkProcessRunner? processRunner,
  }) async {
    final gateways = <String, List<_InterfaceGateway>>{};
    for (final request in [
      ('ipv4', ['-n', 'get', 'default']),
      ('ipv6', ['-n', 'get', '-inet6', 'default']),
    ]) {
      final result = await _runProcess(
        'route',
        request.$2,
        processRunner: processRunner,
      );
      if (result.exitCode != 0) {
        continue;
      }

      final fields = <String, String>{};
      for (final line in (result.stdout as String).split('\n')) {
        final separator = line.indexOf(':');
        if (separator <= 0) {
          continue;
        }
        final key = line.substring(0, separator).trim().toLowerCase();
        final value = line.substring(separator + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          fields[key] = value;
        }
      }

      final interfaceName = fields['interface'];
      final gateway = fields['gateway'];
      if (interfaceName == null || gateway == null) {
        continue;
      }
      gateways
          .putIfAbsent(interfaceName, () => [])
          .add(_InterfaceGateway(ip: gateway, ipVersion: request.$1));
    }
    return gateways;
  }

  Future<Map<String, List<_InterfaceGateway>>> _readLinuxDefaultGateways({
    NetworkProcessRunner? processRunner,
  }) async {
    final gateways = <String, List<_InterfaceGateway>>{};
    for (final request in [
      ('ipv4', ['route', 'show', 'default']),
      ('ipv6', ['-6', 'route', 'show', 'default']),
    ]) {
      final result = await _runProcess(
        'ip',
        request.$2,
        processRunner: processRunner,
      );
      if (result.exitCode != 0) {
        continue;
      }

      for (final line in (result.stdout as String).split('\n')) {
        final match = RegExp(
          r'^default(?:\s+via\s+(\S+))?.*\sdev\s+(\S+)',
        ).firstMatch(line.trim());
        if (match == null) {
          continue;
        }
        final gateway = match.group(1);
        final interfaceName = match.group(2);
        if (interfaceName == null) {
          continue;
        }
        gateways
            .putIfAbsent(interfaceName, () => [])
            .add(_InterfaceGateway(ip: gateway, ipVersion: request.$1));
      }
    }
    return gateways;
  }

  Future<_PathMtuMeasurement?> _runLinuxTracepath(
    _ResolvedRouteTarget target, {
    required _RouteLookupEntry? route,
    required List<_InterfaceInfoEntry> interfaces,
    NetworkProcessRunner? processRunner,
  }) async {
    for (final command in _tracepathCommandsForTarget(target)) {
      try {
        final result = await _runProcess(
          command.$1,
          command.$2,
          processRunner: processRunner,
        );
        final stdout = (result.stdout as String).trim();
        if (stdout.isEmpty) {
          continue;
        }

        int? pathMtu;
        final hops = <_TracepathHop>[];
        for (final line in stdout.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            continue;
          }

          final pmtuMatch = RegExp(r'\bpmtu\s+(\d+)').firstMatch(trimmed);
          if (pmtuMatch != null) {
            pathMtu = int.tryParse(pmtuMatch.group(1)!);
          }

          final hopMatch = RegExp(r'^(\d+)[?:]?:\s+(.*)$').firstMatch(trimmed);
          if (hopMatch == null) {
            continue;
          }

          final details = hopMatch.group(2)!;
          final nodeToken = details.split(RegExp(r'\s+')).first;
          final timeMatch = RegExp(r'([0-9.]+)ms').firstMatch(details);
          final hopPmtuMatch = RegExp(r'\bpmtu\s+(\d+)').firstMatch(details);
          hops.add(
            _TracepathHop(
              hop: int.parse(hopMatch.group(1)!),
              node: nodeToken == '[LOCALHOST]' ? null : nodeToken,
              timeMs: timeMatch == null
                  ? null
                  : double.tryParse(timeMatch.group(1)!),
              pathMtu: hopPmtuMatch == null
                  ? null
                  : int.tryParse(hopPmtuMatch.group(1)!),
              note: details.contains('no reply') ? 'no reply' : null,
            ),
          );
        }

        if (pathMtu != null || hops.isNotEmpty) {
          return _PathMtuMeasurement(
            resolvedIp: target.resolvedIp,
            ipVersion: target.ipVersion,
            pathMtu: pathMtu,
            interfaceName: route?.interfaceName,
            gateway: route?.gateway,
            sourceIp: route?.sourceIp,
            discoveryMethod: command.$1,
            hops: hops,
          );
        }
      } on ProcessException {
        continue;
      }
    }

    return _buildInterfaceMtuFallbackMeasurement(
      target,
      route: route,
      interfaces: interfaces,
      note:
          'tracepath output was unavailable, so this falls back to the egress '
          'interface MTU.',
    );
  }

  _PathMtuMeasurement? _buildInterfaceMtuFallbackMeasurement(
    _ResolvedRouteTarget target, {
    required _RouteLookupEntry? route,
    required List<_InterfaceInfoEntry> interfaces,
    required String note,
  }) {
    final interfaceName = route?.interfaceName;
    if (interfaceName == null) {
      return null;
    }

    final interface = _firstWhereOrNull<_InterfaceInfoEntry>(
      interfaces,
      (entry) => entry.name == interfaceName,
    );
    if (interface?.mtu == null) {
      return null;
    }

    return _PathMtuMeasurement(
      resolvedIp: target.resolvedIp,
      ipVersion: target.ipVersion,
      pathMtu: interface!.mtu,
      interfaceName: interface.name,
      gateway: route?.gateway,
      sourceIp: route?.sourceIp,
      discoveryMethod: 'interface_mtu_fallback',
      notes: [note],
    );
  }

  List<(String, List<String>)> _tracepathCommandsForTarget(
    _ResolvedRouteTarget target,
  ) {
    if (target.ipVersion == 'ipv6') {
      return [
        ('tracepath', ['-6', '-n', target.commandTarget]),
        ('tracepath6', ['-n', target.commandTarget]),
        ('tracepath6', [target.commandTarget]),
      ];
    }
    return [
      ('tracepath', ['-n', target.commandTarget]),
    ];
  }

  int? _ipv4MaskToPrefix(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.startsWith('0x')) {
      final mask = int.tryParse(normalized.substring(2), radix: 16);
      return mask == null ? null : _bitCount(mask);
    }

    final address = InternetAddress.tryParse(normalized);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return null;
    }
    return address.rawAddress.fold<int>(
      0,
      (sum, byte) => sum + _bitCount(byte),
    );
  }

  int _bitCount(int value) {
    var count = 0;
    var current = value;
    while (current > 0) {
      count += current & 1;
      current >>= 1;
    }
    return count;
  }

  String _addressScope(String address) {
    final parsed = InternetAddress.tryParse(
      normalizeNetworkIpForComparison(address),
    );
    if (parsed == null) {
      return 'unknown';
    }
    if (parsed.isLoopback) {
      return 'host';
    }
    if (parsed.type == InternetAddressType.IPv6) {
      final bytes = parsed.rawAddress;
      if (bytes.isNotEmpty && bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) {
        return 'link';
      }
      return 'global';
    }
    final bytes = parsed.rawAddress;
    if (bytes.length >= 2 && bytes[0] == 169 && bytes[1] == 254) {
      return 'link';
    }
    return 'global';
  }

  T? _firstWhereOrNull<T>(
    Iterable<T> values,
    bool Function(T value) predicate,
  ) {
    for (final value in values) {
      if (predicate(value)) {
        return value;
      }
    }
    return null;
  }
}

const Set<String> _linuxSpecialRouteTypes = {
  'local',
  'broadcast',
  'multicast',
  'blackhole',
  'unreachable',
  'prohibit',
  'throw',
};

class _ResolvedRouteTarget {
  const _ResolvedRouteTarget({
    required this.requestedHost,
    required this.commandTarget,
    required this.resolvedIp,
    required this.ipVersion,
  });

  final String requestedHost;
  final String commandTarget;
  final String resolvedIp;
  final String ipVersion;
}

class _RouteLookupEntry {
  const _RouteLookupEntry({
    required this.requestedHost,
    required this.resolvedIp,
    required this.ipVersion,
    this.destination,
    this.gateway,
    this.interfaceName,
    this.sourceIp,
    this.flags,
    this.rawOutput,
  });

  final String requestedHost;
  final String resolvedIp;
  final String ipVersion;
  final String? destination;
  final String? gateway;
  final String? interfaceName;
  final String? sourceIp;
  final String? flags;
  final String? rawOutput;

  Map<String, dynamic> toJson() => {
    'host': requestedHost,
    'resolved_ip': resolvedIp,
    'ip_version': ipVersion,
    if (destination != null) 'destination': destination,
    if (gateway != null) 'gateway': gateway,
    if (interfaceName != null) 'interface': interfaceName,
    if (sourceIp != null) 'source_ip': sourceIp,
    if (flags != null) 'flags': flags,
    if (rawOutput != null) 'raw_output': rawOutput,
  };
}

class _InterfaceInfoEntry {
  const _InterfaceInfoEntry({
    required this.name,
    this.mac,
    this.mtu,
    this.status,
    this.flags = const [],
    this.addresses = const [],
    this.defaultGateways = const [],
  });

  final String name;
  final String? mac;
  final int? mtu;
  final String? status;
  final List<String> flags;
  final List<_InterfaceAddressInfo> addresses;
  final List<_InterfaceGateway> defaultGateways;

  _InterfaceInfoEntry filtered({required String ipVersion}) {
    if (ipVersion == 'all') {
      return this;
    }

    return _InterfaceInfoEntry(
      name: name,
      mac: mac,
      mtu: mtu,
      status: status,
      flags: flags,
      addresses: addresses
          .where((entry) => entry.ipVersion == ipVersion)
          .toList(growable: false),
      defaultGateways: defaultGateways
          .where((entry) => entry.ipVersion == ipVersion)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (mac != null) 'mac': mac,
    if (mtu != null) 'mtu': mtu,
    if (status != null) 'status': status,
    if (flags.isNotEmpty) 'flags': flags,
    'is_up': flags.contains('UP') || status == 'active' || status == 'UP',
    'addresses': addresses.map((entry) => entry.toJson()).toList(),
    if (defaultGateways.isNotEmpty)
      'default_gateways': defaultGateways
          .map((entry) => entry.toJson())
          .toList(),
  };
}

class _InterfaceInfoEntryBuilder {
  _InterfaceInfoEntryBuilder(this.name);

  final String name;
  String? mac;
  int? mtu;
  String? status;
  List<String> flags = const [];
  final List<_InterfaceAddressInfo> addresses = [];
  List<_InterfaceGateway> defaultGateways = const [];

  _InterfaceInfoEntry build() {
    final sortedAddresses = addresses.toList(growable: false)
      ..sort((a, b) => compareNetworkIpAddresses(a.address, b.address));
    return _InterfaceInfoEntry(
      name: name,
      mac: mac,
      mtu: mtu,
      status: status,
      flags: List.unmodifiable(flags),
      addresses: sortedAddresses,
      defaultGateways: List.unmodifiable(defaultGateways),
    );
  }
}

class _InterfaceAddressInfo {
  const _InterfaceAddressInfo({
    required this.address,
    required this.ipVersion,
    required this.scope,
    this.prefixLength,
  });

  final String address;
  final String ipVersion;
  final String scope;
  final int? prefixLength;

  Map<String, dynamic> toJson() => {
    'address': address,
    'ip_version': ipVersion,
    'scope': scope,
    if (prefixLength != null) 'prefix_length': prefixLength,
  };
}

class _InterfaceGateway {
  const _InterfaceGateway({required this.ip, required this.ipVersion});

  final String? ip;
  final String ipVersion;

  Map<String, dynamic> toJson() => {
    if (ip != null) 'ip': ip,
    'ip_version': ipVersion,
  };
}

class _PathMtuMeasurement {
  const _PathMtuMeasurement({
    required this.resolvedIp,
    required this.ipVersion,
    required this.discoveryMethod,
    this.pathMtu,
    this.interfaceName,
    this.gateway,
    this.sourceIp,
    this.notes = const [],
    this.hops = const [],
  });

  final String resolvedIp;
  final String ipVersion;
  final String discoveryMethod;
  final int? pathMtu;
  final String? interfaceName;
  final String? gateway;
  final String? sourceIp;
  final List<String> notes;
  final List<_TracepathHop> hops;

  Map<String, dynamic> toJson() => {
    'resolved_ip': resolvedIp,
    'ip_version': ipVersion,
    'discovery_method': discoveryMethod,
    if (pathMtu != null) 'path_mtu': pathMtu,
    if (interfaceName != null) 'interface': interfaceName,
    if (gateway != null) 'gateway': gateway,
    if (sourceIp != null) 'source_ip': sourceIp,
    if (notes.isNotEmpty) 'notes': notes,
    if (hops.isNotEmpty) 'hops': hops.map((entry) => entry.toJson()).toList(),
  };
}

class _TracepathHop {
  const _TracepathHop({
    required this.hop,
    this.node,
    this.timeMs,
    this.pathMtu,
    this.note,
  });

  final int hop;
  final String? node;
  final double? timeMs;
  final int? pathMtu;
  final String? note;

  Map<String, dynamic> toJson() => {
    'hop': hop,
    if (node != null) 'node': node,
    if (timeMs != null) 'time_ms': timeMs,
    if (pathMtu != null) 'path_mtu': pathMtu,
    if (note != null) 'note': note,
  };
}
