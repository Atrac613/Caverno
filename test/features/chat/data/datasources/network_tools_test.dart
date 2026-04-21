import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:caverno/features/chat/data/datasources/network_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkTools.ping6', () {
    test('resolves a hostname to IPv6 before running the ping', () async {
      late String capturedRequestedHost;
      late String capturedPingTarget;
      late String capturedResolvedIp;
      late String capturedRequestedIpVersion;

      final response =
          jsonDecode(
                await NetworkTools.ping6(
                  host: 'ipv6.example.test',
                  count: 2,
                  timeoutSeconds: 7,
                  addressLookup:
                      (host, {type = InternetAddressType.any}) async {
                        expect(host, 'ipv6.example.test');
                        expect(type, InternetAddressType.IPv6);
                        return [InternetAddress('2001:db8::42')];
                      },
                  pingRunner:
                      ({
                        required requestedHost,
                        required pingTarget,
                        required count,
                        required timeoutSeconds,
                        resolvedIp,
                        requestedIpVersion,
                      }) async {
                        capturedRequestedHost = requestedHost;
                        capturedPingTarget = pingTarget;
                        capturedResolvedIp = resolvedIp ?? '';
                        capturedRequestedIpVersion = requestedIpVersion ?? '';
                        expect(count, 2);
                        expect(timeoutSeconds, 7);
                        return jsonEncode({
                          'host': requestedHost,
                          'ping_target': pingTarget,
                          'resolved_ip': resolvedIp,
                          'ip_version': requestedIpVersion,
                        });
                      },
                ),
              )
              as Map<String, dynamic>;

      expect(capturedRequestedHost, 'ipv6.example.test');
      expect(capturedPingTarget, '2001:db8::42');
      expect(capturedResolvedIp, '2001:db8::42');
      expect(capturedRequestedIpVersion, 'ipv6');
      expect(response['ip_version'], 'ipv6');
      expect(response['resolved_ip'], '2001:db8::42');
    });

    test('rejects IPv4-only literal targets', () async {
      await expectLater(
        () => NetworkTools.ping6(
          host: '192.168.1.1',
          pingRunner:
              ({
                required requestedHost,
                required pingTarget,
                required count,
                required timeoutSeconds,
                resolvedIp,
                requestedIpVersion,
              }) async => '{}',
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('NetworkTools.arp', () {
    test(
      'returns local neighbor cache entries across supported IP versions',
      () async {
        final response =
            jsonDecode(
                  await NetworkTools.arp(
                    processRunner: _processRunnerForPlatform(),
                  ),
                )
                as Map<String, dynamic>;

        final entries = (response['entries'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

        expect(response['ip_version'], 'all');
        expect(response['entries_found'], 2);
        expect(entries.any((entry) => entry['ip_version'] == 'ipv4'), isTrue);
        expect(entries.any((entry) => entry['ip_version'] == 'ipv6'), isTrue);
        expect(entries.any((entry) => entry['source'] == 'arp'), isTrue);
        expect(entries.any((entry) => entry['source'] == 'ndp'), isTrue);
      },
    );

    test('filters entries by host name from the local cache', () async {
      final hostFilter = Platform.isMacOS ? 'router' : '192.168.1.1';
      final response =
          jsonDecode(
                await NetworkTools.arp(
                  host: hostFilter,
                  processRunner: _processRunnerForPlatform(),
                ),
              )
              as Map<String, dynamic>;

      final entries = (response['entries'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['entries_found'], 1);
      expect(entries.single['ip'], '192.168.1.1');
      if (Platform.isMacOS) {
        expect(entries.single['hostname'], 'router');
      }
    });

    test('returns only IPv6 entries when requested', () async {
      final response =
          jsonDecode(
                await NetworkTools.arp(
                  ipVersion: 'ipv6',
                  processRunner: _processRunnerForPlatform(),
                ),
              )
              as Map<String, dynamic>;

      final entries = (response['entries'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['entries_found'], 1);
      expect(entries.single['ip_version'], 'ipv6');
      expect(entries.single['source'], 'ndp');
    });
  });

  group('NetworkTools.ndp', () {
    test('returns only IPv6 neighbor entries', () async {
      final response =
          jsonDecode(
                await NetworkTools.ndp(
                  processRunner: _processRunnerForPlatform(),
                ),
              )
              as Map<String, dynamic>;

      final entries = (response['entries'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['ip_version'], 'ipv6');
      expect(response['entries_found'], 1);
      expect(entries.single['ip_version'], 'ipv6');
      expect(entries.single['source'], 'ndp');
    });
  });

  group('NetworkTools.routeLookup', () {
    test(
      'returns route selection details for dual-stack destinations',
      () async {
        final response =
            jsonDecode(
                  await NetworkTools.routeLookup(
                    host: 'example.test',
                    addressLookup: _dualStackLookup,
                    processRunner: _processRunnerForPlatform(),
                  ),
                )
                as Map<String, dynamic>;

        final routes = (response['routes'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

        expect(response['routes_found'], 2);
        expect(
          routes.any(
            (route) =>
                route['ip_version'] == 'ipv4' &&
                route['interface'] == _primaryInterfaceName,
          ),
          isTrue,
        );
        expect(
          routes.any(
            (route) =>
                route['ip_version'] == 'ipv6' &&
                route['gateway'] == _ipv6Gateway,
          ),
          isTrue,
        );
      },
    );
  });

  group('NetworkTools.interfaceInfo', () {
    test('returns interface addresses, mtu, and default gateways', () async {
      final response =
          jsonDecode(
                await NetworkTools.interfaceInfo(
                  interfaceName: _primaryInterfaceName,
                  processRunner: _processRunnerForPlatform(),
                ),
              )
              as Map<String, dynamic>;

      final interfaces = (response['interfaces'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final interface = interfaces.single;
      final addresses = (interface['addresses'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final gateways = (interface['default_gateways'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['interfaces_found'], 1);
      expect(interface['name'], _primaryInterfaceName);
      expect(interface['mtu'], 1500);
      expect(
        addresses.any(
          (address) =>
              address['ip_version'] == 'ipv4' &&
              address['address'] == '192.168.1.20',
        ),
        isTrue,
      );
      expect(
        addresses.any((address) => address['ip_version'] == 'ipv6'),
        isTrue,
      );
      expect(
        gateways.any(
          (gateway) =>
              gateway['ip_version'] == 'ipv4' && gateway['ip'] == '192.168.1.1',
        ),
        isTrue,
      );
      expect(
        gateways.any(
          (gateway) =>
              gateway['ip_version'] == 'ipv6' && gateway['ip'] == _ipv6Gateway,
        ),
        isTrue,
      );
    });
  });

  group('NetworkTools.dnsQuery', () {
    test('resolves AAAA records explicitly', () async {
      final response =
          jsonDecode(
                await NetworkTools.dnsQuery(
                  target: 'example.test',
                  recordType: 'AAAA',
                  addressLookup: _dualStackLookup,
                ),
              )
              as Map<String, dynamic>;

      final records = (response['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['record_type'], 'AAAA');
      expect(records.single['value'], '2001:db8::80');
    });

    test('returns PTR records from reverse lookup', () async {
      final response =
          jsonDecode(
                await NetworkTools.dnsQuery(
                  target: '192.168.1.1',
                  recordType: 'PTR',
                  reverseLookup: (address) async => _FakeInternetAddress(
                    address: address.address,
                    host: 'router.local',
                    type: address.type,
                  ),
                ),
              )
              as Map<String, dynamic>;

      final records = (response['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['record_type'], 'PTR');
      expect(records.single['value'], 'router.local');
    });

    test('parses CNAME responses from nslookup', () async {
      final response =
          jsonDecode(
                await NetworkTools.dnsQuery(
                  target: 'www.example.test',
                  recordType: 'CNAME',
                  processRunner: _processRunnerForPlatform(),
                ),
              )
              as Map<String, dynamic>;

      final records = (response['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['record_type'], 'CNAME');
      expect(records.single['value'], 'edge.example.test.');
    });
  });

  group('NetworkTools.pathMtu', () {
    test('reports discovered or fallback MTU information', () async {
      final response =
          jsonDecode(
                await NetworkTools.pathMtu(
                  host: 'example.test',
                  ipVersion: 'ipv4',
                  addressLookup: _dualStackLookup,
                  processRunner: _processRunnerForPlatform(),
                ),
              )
              as Map<String, dynamic>;

      final measurements = (response['measurements'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final measurement = measurements.single;

      expect(response['measurements_found'], 1);
      expect(measurement['path_mtu'], Platform.isLinux ? 1480 : 1500);
      expect(
        measurement['discovery_method'],
        Platform.isLinux ? 'tracepath' : 'interface_mtu_fallback',
      );
      expect(measurement['interface'], _primaryInterfaceName);
    });
  });

  group('NetworkTools.mdnsBrowse', () {
    test('returns formatted mDNS browse payloads', () async {
      final response =
          jsonDecode(
                await NetworkTools.mdnsBrowse(
                  serviceType: '_ipp._tcp.local',
                  browseRunner:
                      ({
                        required serviceType,
                        required timeoutMs,
                        required maxResults,
                        required ipVersion,
                      }) async {
                        expect(serviceType, '_ipp._tcp.local');
                        expect(timeoutMs, 2000);
                        expect(maxResults, 50);
                        expect(ipVersion, 'all');
                        return {
                          'service_type': serviceType,
                          'ip_version': ipVersion,
                          'services_found': 1,
                          'services': [
                            {
                              'service_instance':
                                  'Office Printer._ipp._tcp.local',
                              'service_type': serviceType,
                              'targets': [
                                {
                                  'host': 'printer.local',
                                  'port': 631,
                                  'priority': 0,
                                  'weight': 0,
                                  'addresses': ['192.168.1.50', 'fe80::50'],
                                },
                              ],
                            },
                          ],
                        };
                      },
                ),
              )
              as Map<String, dynamic>;

      final services = (response['services'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final targets = (services.single['targets'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(response['services_found'], 1);
      expect(
        services.single['service_instance'],
        'Office Printer._ipp._tcp.local',
      );
      expect(targets.single['host'], 'printer.local');
    });
  });
}

NetworkProcessRunner _processRunnerForPlatform() {
  return (executable, arguments) async {
    if (Platform.isMacOS) {
      if (executable == 'arp' && arguments.join(' ') == '-a') {
        return ProcessResult(
          0,
          0,
          'router (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]\n',
          '',
        );
      }
      if (executable == 'ndp' && arguments.join(' ') == '-an') {
        return ProcessResult(
          0,
          0,
          'Neighbor Linklayer Address Netif Expire S Flags\n'
              'fe80::1%en0 aa:bb:cc:dd:ee:ff en0 23h59m59s S R\n',
          '',
        );
      }
      if (executable == 'route' &&
          arguments.join(' ') == '-n get 93.184.216.34') {
        return ProcessResult(
          0,
          0,
          '   route to: 93.184.216.34\n'
              'destination: 93.184.216.34\n'
              '    gateway: 192.168.1.1\n'
              '  interface: en0\n'
              ' if address: 192.168.1.20\n'
              '      flags: <UP,GATEWAY,DONE,STATIC>\n',
          '',
        );
      }
      if (executable == 'route' &&
          arguments.join(' ') == '-n get -inet6 2001:db8::80') {
        return ProcessResult(
          0,
          0,
          '   route to: 2001:db8::80\n'
              'destination: 2001:db8::80\n'
              '    gateway: fe80::1%en0\n'
              '  interface: en0\n'
              ' if address: 2001:db8::20\n'
              '      flags: <UP,GATEWAY,DONE,STATIC>\n',
          '',
        );
      }
      if (executable == 'route' && arguments.join(' ') == '-n get default') {
        return ProcessResult(
          0,
          0,
          '   route to: default\n'
              'destination: default\n'
              '    gateway: 192.168.1.1\n'
              '  interface: en0\n',
          '',
        );
      }
      if (executable == 'route' &&
          arguments.join(' ') == '-n get -inet6 default') {
        return ProcessResult(
          0,
          0,
          '   route to: default\n'
              'destination: default\n'
              '    gateway: fe80::1%en0\n'
              '  interface: en0\n',
          '',
        );
      }
      if (executable == 'ifconfig' && arguments.isEmpty) {
        return ProcessResult(
          0,
          0,
          'en0: flags=8863<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n'
              '    ether aa:bb:cc:dd:ee:ff\n'
              '    inet 192.168.1.20 netmask 0xffffff00 broadcast 192.168.1.255\n'
              '    inet6 2001:db8::20 prefixlen 64 autoconf\n'
              '    inet6 fe80::20%en0 prefixlen 64 scopeid 0x4\n'
              '    status: active\n',
          '',
        );
      }
      if (executable == 'nslookup' &&
          arguments.join(' ') == '-type=cname www.example.test') {
        return ProcessResult(
          0,
          0,
          'Server:\t192.168.1.1\n'
              'Address:\t192.168.1.1#53\n\n'
              'Non-authoritative answer:\n'
              'www.example.test\tcanonical name = edge.example.test.\n',
          '',
        );
      }
    }

    if (Platform.isLinux) {
      if (executable == 'ip' && arguments.join(' ') == 'neighbor show') {
        return ProcessResult(
          0,
          0,
          '192.168.1.1 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE\n',
          '',
        );
      }
      if (executable == 'ip' && arguments.join(' ') == '-6 neighbor show') {
        return ProcessResult(
          0,
          0,
          'fe80::1 dev eth0 lladdr aa:bb:cc:dd:ee:ff router REACHABLE\n',
          '',
        );
      }
      if (executable == 'ip' &&
          arguments.join(' ') == 'route get 93.184.216.34') {
        return ProcessResult(
          0,
          0,
          '93.184.216.34 via 192.168.1.1 dev eth0 src 192.168.1.20 uid 1000\n',
          '',
        );
      }
      if (executable == 'ip' &&
          arguments.join(' ') == '-6 route get 2001:db8::80') {
        return ProcessResult(
          0,
          0,
          '2001:db8::80 via fe80::1 dev eth0 src 2001:db8::20 metric 100 pref medium\n',
          '',
        );
      }
      if (executable == 'ip' && arguments.join(' ') == 'route show default') {
        return ProcessResult(0, 0, 'default via 192.168.1.1 dev eth0\n', '');
      }
      if (executable == 'ip' &&
          arguments.join(' ') == '-6 route show default') {
        return ProcessResult(
          0,
          0,
          'default via fe80::1 dev eth0 metric 100\n',
          '',
        );
      }
      if (executable == 'ip' && arguments.join(' ') == 'addr show') {
        return ProcessResult(
          0,
          0,
          '2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP\n'
              '    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff\n'
              '    inet 192.168.1.20/24 brd 192.168.1.255 scope global eth0\n'
              '    inet6 2001:db8::20/64 scope global dynamic\n'
              '    inet6 fe80::20/64 scope link\n',
          '',
        );
      }
      if (executable == 'tracepath' &&
          arguments.join(' ') == '-n 93.184.216.34') {
        return ProcessResult(
          0,
          0,
          ' 1?: [LOCALHOST]                      pmtu 1500\n'
              ' 1:  192.168.1.1                     1.123ms\n'
              ' 2:  10.0.0.1                        4.321ms pmtu 1480\n'
              ' 3:  93.184.216.34                   9.876ms reached\n'
              '     Resume: pmtu 1480 hops 3 back 3\n',
          '',
        );
      }
      if (executable == 'nslookup' &&
          arguments.join(' ') == '-type=cname www.example.test') {
        return ProcessResult(
          0,
          0,
          'Server:\t127.0.0.53\n'
              'Address:\t127.0.0.53#53\n\n'
              'Non-authoritative answer:\n'
              'www.example.test\tcanonical name = edge.example.test.\n',
          '',
        );
      }
    }

    return ProcessResult(0, 0, '', '');
  };
}

Future<List<InternetAddress>> _dualStackLookup(
  String host, {
  InternetAddressType type = InternetAddressType.any,
}) async {
  expect(host, 'example.test');
  return switch (type) {
    InternetAddressType.IPv4 => [InternetAddress('93.184.216.34')],
    InternetAddressType.IPv6 => [InternetAddress('2001:db8::80')],
    _ => [InternetAddress('93.184.216.34'), InternetAddress('2001:db8::80')],
  };
}

String get _primaryInterfaceName => Platform.isMacOS ? 'en0' : 'eth0';

String get _ipv6Gateway => Platform.isMacOS ? 'fe80::1%en0' : 'fe80::1';

class _FakeInternetAddress implements InternetAddress {
  _FakeInternetAddress({
    required this.address,
    required this.host,
    required this.type,
  });

  @override
  final String address;

  @override
  final String host;

  @override
  final InternetAddressType type;

  @override
  bool get isLinkLocal => false;

  @override
  bool get isLoopback => false;

  @override
  bool get isMulticast => false;

  @override
  Uint8List get rawAddress => InternetAddress(address).rawAddress;

  @override
  Future<InternetAddress> reverse() async => this;
}
