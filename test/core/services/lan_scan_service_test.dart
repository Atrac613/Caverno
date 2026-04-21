import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/lan_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LanScanService', () {
    test('discovers IPv6 neighbors from the local link cache', () async {
      expect(Platform.isMacOS || Platform.isLinux, isTrue);

      final probedIps = <String>[];
      final service = LanScanService(
        wifiIpv6Provider: () async => 'fe80::1234%en0',
        processRunner: _neighborProcessRunner([
          const _NeighborEntry(
            ip: 'fe80::abcd',
            mac: '00:11:22:33:44:55',
            interfaceName: 'en0',
          ),
          const _NeighborEntry(
            ip: 'ff02::1',
            mac: '33:33:00:00:00:01',
            interfaceName: 'en0',
          ),
        ]),
        hostProbe:
            ({
              required String ip,
              required int timeoutMs,
              required List<int> ports,
              required Map<String, LanLinkLayerEntry> linkLayerTable,
            }) async {
              probedIps.add(ip);
              return LanHost(ip: ip, mac: linkLayerTable[ip]?.mac);
            },
      );

      final response =
          jsonDecode(await service.startScan(ipVersion: 'ipv6'))
              as Map<String, dynamic>;
      final hosts = response['hosts'] as List<dynamic>;

      expect(response['hosts_found'], 1);
      expect(response['address_families'], ['ipv6']);
      expect(response['scan_strategy'], 'ipv6_neighbors');
      expect(probedIps, hasLength(1));
      expect(probedIps.single, contains('fe80::abcd'));
      expect((hosts.single as Map<String, dynamic>)['ip_version'], 'ipv6');
      expect(hosts.single['mac'], '00:11:22:33:44:55');
    });

    test('enumerates explicit small IPv6 CIDR ranges', () async {
      final probedIps = <String>[];
      final service = LanScanService(
        processRunner: _neighborProcessRunner(const []),
        hostProbe:
            ({
              required String ip,
              required int timeoutMs,
              required List<int> ports,
              required Map<String, LanLinkLayerEntry> linkLayerTable,
            }) async {
              probedIps.add(ip);
              return ip == 'fd00::2' ? LanHost(ip: ip) : null;
            },
      );

      final response =
          jsonDecode(
                await service.startScan(
                  subnet: 'fd00::/126',
                  ipVersion: 'ipv6',
                ),
              )
              as Map<String, dynamic>;

      expect(probedIps, ['fd00::1', 'fd00::2', 'fd00::3']);
      expect(response['hosts_scanned'], 3);
      expect(response['hosts_found'], 1);
      expect(response['scan_strategy'], 'explicit_ipv6_cidr');
    });

    test('filters wide IPv6 subnets through neighbor discovery', () async {
      expect(Platform.isMacOS || Platform.isLinux, isTrue);

      final probedIps = <String>[];
      final service = LanScanService(
        processRunner: _neighborProcessRunner([
          const _NeighborEntry(
            ip: 'fd00::10',
            mac: '00:aa:bb:cc:dd:ee',
            interfaceName: 'en0',
          ),
          const _NeighborEntry(
            ip: '2001:db8::20',
            mac: '00:ff:ee:dd:cc:bb',
            interfaceName: 'en0',
          ),
        ]),
        hostProbe:
            ({
              required String ip,
              required int timeoutMs,
              required List<int> ports,
              required Map<String, LanLinkLayerEntry> linkLayerTable,
            }) async {
              probedIps.add(ip);
              return LanHost(ip: ip);
            },
      );

      final response =
          jsonDecode(
                await service.startScan(subnet: 'fd00::/64', ipVersion: 'ipv6'),
              )
              as Map<String, dynamic>;

      expect(probedIps, ['fd00::10']);
      expect(response['hosts_scanned'], 1);
      expect(response['hosts_found'], 1);
      expect(response['scan_strategy'], 'ipv6_neighbor_table_filtered');
    });
  });
}

typedef _Runner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class _NeighborEntry {
  const _NeighborEntry({
    required this.ip,
    required this.mac,
    required this.interfaceName,
  });

  final String ip;
  final String mac;
  final String interfaceName;
}

_Runner _neighborProcessRunner(List<_NeighborEntry> entries) {
  return (executable, arguments) async {
    if (executable == 'arp') {
      return ProcessResult(0, 0, '', '');
    }

    if (Platform.isMacOS && executable == 'ndp') {
      final lines = <String>[
        'Neighbor Linklayer Address Netif Expire S Flags',
        for (final entry in entries)
          '${entry.ip} ${entry.mac} ${entry.interfaceName} 23h59m59s S R',
      ];
      return ProcessResult(0, 0, '${lines.join('\n')}\n', '');
    }

    if (Platform.isLinux && executable == 'ip') {
      final lines = entries
          .map(
            (entry) =>
                '${entry.ip} dev ${entry.interfaceName} lladdr ${entry.mac} REACHABLE',
          )
          .join('\n');
      return ProcessResult(0, 0, lines.isEmpty ? '' : '$lines\n', '');
    }

    return ProcessResult(0, 0, '', '');
  };
}
