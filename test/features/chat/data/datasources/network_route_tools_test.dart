import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/network_route_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkRouteTools validation', () {
    test('rejects invalid address families before platform IO', () async {
      final tools = NetworkRouteTools(
        platform: NetworkRoutePlatform.unsupported,
      );

      final route = _decode(
        await tools.routeLookup(host: 'example.test', ipVersion: 'v4'),
      );
      final interface = _decode(await tools.interfaceInfo(ipVersion: 'auto'));
      final pathMtu = _decode(
        await tools.pathMtu(host: 'example.test', ipVersion: 'all'),
      );

      expect(route, {
        'error': true,
        'message': 'ip_version must be one of: auto, ipv4, ipv6',
      });
      expect(interface, {
        'error': true,
        'message': 'ip_version must be one of: all, ipv4, ipv6',
      });
      expect(pathMtu, route);
    });

    test('reports unsupported route diagnostics explicitly', () async {
      final tools = NetworkRouteTools(
        platform: NetworkRoutePlatform.unsupported,
      );

      expect(_decode(await tools.routeLookup(host: '192.0.2.1')), {
        'error': true,
        'message': 'Route inspection is only supported on macOS and Linux.',
      });
      expect(_decode(await tools.pathMtu(host: '192.0.2.1')), {
        'error': true,
        'message': 'Path MTU discovery is only supported on macOS and Linux.',
      });
    });
  });

  group('NetworkRouteTools.routeLookup', () {
    for (final fixture in _PlatformFixture.values) {
      test('parses dual-stack ${fixture.label} routes', () async {
        final process = _FixtureProcessRunner(fixture);
        final response = _decode(
          await NetworkRouteTools(platform: fixture.platform).routeLookup(
            host: 'example.test',
            addressLookup: _dualStackLookup,
            processRunner: process.call,
          ),
        );
        final routes = _maps(response['routes']);

        expect(response['host'], 'example.test');
        expect(response['ip_version'], 'auto');
        expect(response['routes_found'], 2);
        expect(routes.map((route) => route['ip_version']), ['ipv4', 'ipv6']);
        expect(routes.first['destination'], '93.184.216.34');
        expect(routes.first['gateway'], '192.168.1.1');
        expect(routes.first['interface'], fixture.interfaceName);
        expect(routes.first['source_ip'], '192.168.1.20');
        expect(routes.last['gateway'], fixture.ipv6Gateway);
        expect(routes.last['source_ip'], '2001:db8::20');
      });
    }

    test(
      'filters mismatched literal address families without lookup',
      () async {
        var processCalled = false;
        var lookupCalled = false;
        final response = _decode(
          await NetworkRouteTools(
            platform: NetworkRoutePlatform.linux,
          ).routeLookup(
            host: '192.0.2.1',
            ipVersion: 'ipv6',
            addressLookup: (host, {type = InternetAddressType.any}) async {
              lookupCalled = true;
              return const [];
            },
            processRunner: (executable, arguments) async {
              processCalled = true;
              return ProcessResult(0, 0, '', '');
            },
          ),
        );

        expect(response['routes_found'], 0);
        expect(response['routes'], isEmpty);
        expect(lookupCalled, isFalse);
        expect(processCalled, isFalse);
      },
    );

    test('keeps the available family when auto lookup partly fails', () async {
      final process = _FixtureProcessRunner(_PlatformFixture.linux);
      final response = _decode(
        await NetworkRouteTools(
          platform: NetworkRoutePlatform.linux,
        ).routeLookup(
          host: 'ipv6-only.test',
          addressLookup: (host, {type = InternetAddressType.any}) async {
            if (type == InternetAddressType.IPv4) {
              throw const SocketException('No IPv4 record');
            }
            return [InternetAddress('2001:db8::80')];
          },
          processRunner: process.call,
        ),
      );

      expect(response['routes_found'], 1);
      expect(_maps(response['routes']).single['ip_version'], 'ipv6');
    });

    test('omits failed and empty Linux route results', () async {
      var invocation = 0;
      final response = _decode(
        await NetworkRouteTools(
          platform: NetworkRoutePlatform.linux,
        ).routeLookup(
          host: 'example.test',
          addressLookup: _dualStackLookup,
          processRunner: (executable, arguments) async {
            invocation += 1;
            return invocation == 1
                ? ProcessResult(0, 1, '', 'unreachable')
                : ProcessResult(0, 0, '\n', '');
          },
        ),
      );

      expect(response['routes_found'], 0);
      expect(response['routes'], isEmpty);
    });
  });

  group('NetworkRouteTools.interfaceInfo', () {
    for (final fixture in _PlatformFixture.values) {
      test('parses and filters ${fixture.label} interface details', () async {
        final process = _FixtureProcessRunner(fixture);
        final response = _decode(
          await NetworkRouteTools(platform: fixture.platform).interfaceInfo(
            interfaceName: ' ${fixture.interfaceName} ',
            ipVersion: 'IPv6',
            processRunner: process.call,
          ),
        );
        final interface = _maps(response['interfaces']).single;
        final addresses = _maps(interface['addresses']);
        final gateways = _maps(interface['default_gateways']);

        expect(response['interface'], fixture.interfaceName);
        expect(response['ip_version'], 'ipv6');
        expect(response['interfaces_found'], 1);
        expect(interface['name'], fixture.interfaceName);
        expect(interface['mac'], 'aa:bb:cc:dd:ee:ff');
        expect(interface['mtu'], 1500);
        expect(interface['is_up'], isTrue);
        expect(addresses, hasLength(fixture == _PlatformFixture.macos ? 1 : 2));
        expect(
          addresses.every((entry) => entry['ip_version'] == 'ipv6'),
          isTrue,
        );
        expect(addresses.first['address'], '2001:db8::20');
        expect(addresses.first['prefix_length'], 64);
        if (fixture == _PlatformFixture.linux) {
          expect(addresses.last['scope'], 'link');
        }
        expect(gateways, [
          {'ip': fixture.ipv6Gateway, 'ip_version': 'ipv6'},
        ]);
      });
    }

    test('returns no entries for a missing requested interface', () async {
      final process = _FixtureProcessRunner(_PlatformFixture.macos);
      final response = _decode(
        await NetworkRouteTools(
          platform: NetworkRoutePlatform.macos,
        ).interfaceInfo(interfaceName: 'en99', processRunner: process.call),
      );

      expect(response['interfaces_found'], 0);
      expect(response['interfaces'], isEmpty);
    });
  });

  group('NetworkRouteTools.pathMtu', () {
    test('uses the macOS egress interface MTU fallback', () async {
      final process = _FixtureProcessRunner(_PlatformFixture.macos);
      final response = _decode(
        await NetworkRouteTools(platform: NetworkRoutePlatform.macos).pathMtu(
          host: 'example.test',
          ipVersion: 'ipv4',
          addressLookup: _dualStackLookup,
          processRunner: process.call,
        ),
      );
      final measurement = _maps(response['measurements']).single;

      expect(response['measurements_found'], 1);
      expect(measurement['resolved_ip'], '93.184.216.34');
      expect(measurement['path_mtu'], 1500);
      expect(measurement['interface'], 'en0');
      expect(measurement['gateway'], '192.168.1.1');
      expect(measurement['discovery_method'], 'interface_mtu_fallback');
      expect(
        (measurement['notes'] as List<dynamic>).single,
        contains('macOS fallback'),
      );
    });

    test('parses Linux tracepath MTU and hop details', () async {
      final process = _FixtureProcessRunner(_PlatformFixture.linux);
      final response = _decode(
        await NetworkRouteTools(platform: NetworkRoutePlatform.linux).pathMtu(
          host: 'example.test',
          ipVersion: 'ipv4',
          addressLookup: _dualStackLookup,
          processRunner: process.call,
        ),
      );
      final measurement = _maps(response['measurements']).single;
      final hops = _maps(measurement['hops']);

      expect(measurement['path_mtu'], 1480);
      expect(measurement['interface'], 'eth0');
      expect(measurement['discovery_method'], 'tracepath');
      expect(hops, hasLength(4));
      expect(hops.first['node'], isNull);
      expect(hops.first['path_mtu'], 1500);
      expect(hops[1]['node'], '192.168.1.1');
      expect(hops[1]['time_ms'], 1.123);
      expect(hops[2]['path_mtu'], 1480);
    });

    test('tries IPv6 tracepath alternatives in order', () async {
      final base = _FixtureProcessRunner(_PlatformFixture.linux);
      final tracepathCalls = <String>[];
      final response = _decode(
        await NetworkRouteTools(platform: NetworkRoutePlatform.linux).pathMtu(
          host: '2001:db8::80',
          ipVersion: 'ipv6',
          processRunner: (executable, arguments) async {
            if (executable.startsWith('tracepath')) {
              tracepathCalls.add('$executable ${arguments.join(' ')}');
              if (tracepathCalls.length == 1) {
                throw ProcessException(executable, arguments);
              }
              if (tracepathCalls.length == 2) {
                return ProcessResult(0, 0, '', '');
              }
              return ProcessResult(
                0,
                0,
                ' 1?: [LOCALHOST] pmtu 1280\n'
                    ' 2: 2001:db8::80 3.5ms reached\n',
                '',
              );
            }
            return base.call(executable, arguments);
          },
        ),
      );
      final measurement = _maps(response['measurements']).single;

      expect(tracepathCalls, [
        'tracepath -6 -n 2001:db8::80',
        'tracepath6 -n 2001:db8::80',
        'tracepath6 2001:db8::80',
      ]);
      expect(measurement['path_mtu'], 1280);
      expect(measurement['discovery_method'], 'tracepath6');
    });

    test(
      'falls back to the Linux interface MTU without tracepath output',
      () async {
        final base = _FixtureProcessRunner(_PlatformFixture.linux);
        final response = _decode(
          await NetworkRouteTools(platform: NetworkRoutePlatform.linux).pathMtu(
            host: '192.0.2.1',
            processRunner: (executable, arguments) async {
              if (executable == 'tracepath') {
                return ProcessResult(0, 1, '', 'not found');
              }
              if (executable == 'ip' &&
                  arguments.join(' ') == 'route get 192.0.2.1') {
                return ProcessResult(
                  0,
                  0,
                  '192.0.2.1 via 192.168.1.1 dev eth0 src 192.168.1.20\n',
                  '',
                );
              }
              return base.call(executable, arguments);
            },
          ),
        );
        final measurement = _maps(response['measurements']).single;

        expect(measurement['path_mtu'], 1500);
        expect(measurement['discovery_method'], 'interface_mtu_fallback');
        expect(
          (measurement['notes'] as List<dynamic>).single,
          contains('tracepath output was unavailable'),
        );
      },
    );
  });
}

Map<String, dynamic> _decode(String value) {
  return jsonDecode(value) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _maps(Object? value) {
  return (value as List<dynamic>).cast<Map<String, dynamic>>();
}

Future<List<InternetAddress>> _dualStackLookup(
  String host, {
  InternetAddressType type = InternetAddressType.any,
}) async {
  return switch (type) {
    InternetAddressType.IPv4 => [InternetAddress('93.184.216.34')],
    InternetAddressType.IPv6 => [InternetAddress('2001:db8::80')],
    _ => [InternetAddress('93.184.216.34'), InternetAddress('2001:db8::80')],
  };
}

enum _PlatformFixture {
  macos(
    label: 'macOS',
    platform: NetworkRoutePlatform.macos,
    interfaceName: 'en0',
    ipv6Gateway: 'fe80::1%en0',
  ),
  linux(
    label: 'Linux',
    platform: NetworkRoutePlatform.linux,
    interfaceName: 'eth0',
    ipv6Gateway: 'fe80::1',
  );

  const _PlatformFixture({
    required this.label,
    required this.platform,
    required this.interfaceName,
    required this.ipv6Gateway,
  });

  final String label;
  final NetworkRoutePlatform platform;
  final String interfaceName;
  final String ipv6Gateway;
}

class _FixtureProcessRunner {
  const _FixtureProcessRunner(this.fixture);

  final _PlatformFixture fixture;

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    final command = '$executable ${arguments.join(' ')}'.trim();
    if (fixture == _PlatformFixture.macos) {
      return _runMacOs(command);
    }
    return _runLinux(command);
  }

  ProcessResult _runMacOs(String command) {
    return switch (command) {
      'route -n get 93.184.216.34' => ProcessResult(
        0,
        0,
        '   route to: 93.184.216.34\n'
            'destination: 93.184.216.34\n'
            '    gateway: 192.168.1.1\n'
            '  interface: en0\n'
            ' if address: 192.168.1.20\n'
            '      flags: <UP,GATEWAY,DONE,STATIC>\n',
        '',
      ),
      'route -n get -inet6 2001:db8::80' => ProcessResult(
        0,
        0,
        '   route to: 2001:db8::80\n'
            'destination: 2001:db8::80\n'
            '    gateway: fe80::1%en0\n'
            '  interface: en0\n'
            ' if address: 2001:db8::20\n'
            '      flags: <UP,GATEWAY,DONE,STATIC>\n',
        '',
      ),
      'route -n get default' => ProcessResult(
        0,
        0,
        '   route to: default\n'
            'destination: default\n'
            '    gateway: 192.168.1.1\n'
            '  interface: en0\n',
        '',
      ),
      'route -n get -inet6 default' => ProcessResult(
        0,
        0,
        '   route to: default\n'
            'destination: default\n'
            '    gateway: fe80::1%en0\n'
            '  interface: en0\n',
        '',
      ),
      'ifconfig' => ProcessResult(
        0,
        0,
        'en0: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n'
            '    ether aa:bb:cc:dd:ee:ff\n'
            '    inet 192.168.1.20 netmask 0xffffff00 broadcast 192.168.1.255\n'
            '    inet6 2001:db8::20 prefixlen 64 autoconf\n'
            '    inet6 fe80::20%en0 prefixlen 64 scopeid 0x4\n'
            '    status: active\n',
        '',
      ),
      _ => ProcessResult(0, 1, '', 'Unexpected command: $command'),
    };
  }

  ProcessResult _runLinux(String command) {
    return switch (command) {
      'ip route get 93.184.216.34' => ProcessResult(
        0,
        0,
        '93.184.216.34 via 192.168.1.1 dev eth0 src 192.168.1.20 uid 1000\n',
        '',
      ),
      'ip -6 route get 2001:db8::80' => ProcessResult(
        0,
        0,
        '2001:db8::80 via fe80::1 dev eth0 src 2001:db8::20 metric 100 pref medium\n',
        '',
      ),
      'ip route show default' => ProcessResult(
        0,
        0,
        'default via 192.168.1.1 dev eth0\n',
        '',
      ),
      'ip -6 route show default' => ProcessResult(
        0,
        0,
        'default via fe80::1 dev eth0 metric 100\n',
        '',
      ),
      'ip addr show' => ProcessResult(
        0,
        0,
        '2: eth0@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP\n'
            '    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff\n'
            '    inet 192.168.1.20/24 brd 192.168.1.255 scope global eth0\n'
            '    inet6 2001:db8::20/64 scope global dynamic\n'
            '    inet6 fe80::20/64 scope link\n',
        '',
      ),
      'tracepath -n 93.184.216.34' => ProcessResult(
        0,
        0,
        ' 1?: [LOCALHOST]                      pmtu 1500\n'
            ' 1:  192.168.1.1                     1.123ms\n'
            ' 2:  10.0.0.1                        4.321ms pmtu 1480\n'
            ' 3:  93.184.216.34                   9.876ms reached\n'
            '     Resume: pmtu 1480 hops 3 back 3\n',
        '',
      ),
      _ => ProcessResult(0, 1, '', 'Unexpected command: $command'),
    };
  }
}
