import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/network_address_utils.dart';
import 'package:caverno/features/chat/data/datasources/network_neighbor_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS ARP and NDP parsing preserves filtering and ordering', () async {
    final runner = _FakeProcessRunner({
      'arp -a': _result(
        'router (192.168.1.10) at AA:BB:CC:DD:EE:10 on en0\n'
        '? (192.168.1.2) at AA:BB:CC:DD:EE:02 on en0\n'
        'ignored (192.168.1.3) at (incomplete) on en0\n'
        'broadcast (192.168.1.255) at ff:ff:ff:ff:ff:ff on en0\n'
        'malformed line\n',
      ),
      'ndp -an': _result(
        'Neighbor Linklayer Address Netif Expire S Flags\n'
        'fe80::2%en0 AA:BB:CC:DD:EE:20 en0 23h59m59s S R\n'
        '2001:db8::10 AA:BB:CC:DD:EE:30 en0 permanent R\n'
        '2001:db8::20 (incomplete) en0 expired\n',
      ),
    });
    final tools = NetworkNeighborTools(platform: NetworkNeighborPlatform.macOs);

    final result = _decode(await tools.arp(processRunner: runner.call));
    final entries = _entries(result);

    expect(runner.calls, ['arp -a', 'ndp -an']);
    expect(result['host'], isNull);
    expect(result['ip_version'], 'all');
    expect(result['entries_found'], 4);
    expect(entries.map((entry) => entry['ip']), [
      '192.168.1.2',
      '192.168.1.10',
      '2001:db8::10',
      'fe80::2%en0',
    ]);
    expect(entries[0], {
      'ip': '192.168.1.2',
      'ip_version': 'ipv4',
      'source': 'arp',
      'mac': 'aa:bb:cc:dd:ee:02',
      'interface': 'en0',
    });
    expect(entries[1]['hostname'], 'router');
    expect(entries.last['state'], 'R');

    final hostnameMatch = _decode(
      await tools.arp(host: ' ROUT ', processRunner: runner.call),
    );
    expect(_entries(hostnameMatch).single['ip'], '192.168.1.10');

    final scopedIpMatch = _decode(
      await tools.arp(host: 'fe80::2', processRunner: runner.call),
    );
    expect(_entries(scopedIpMatch).single['ip'], 'fe80::2%en0');
  });

  test('Linux parsing preserves commands, states, and rejected rows', () async {
    final runner = _FakeProcessRunner({
      'ip neighbor show': _result(
        '192.168.1.10 dev eth0 lladdr AA:BB:CC:DD:EE:10 STALE\n'
        '192.168.1.2 dev eth0 lladdr AA:BB:CC:DD:EE:02 REACHABLE\n'
        '192.168.1.3 dev eth0 FAILED\n'
        '192.168.1.4 dev eth0 INCOMPLETE\n'
        '192.168.1.5 dev eth0 lladdr ff:ff:ff:ff:ff:ff STALE\n'
        '192.168.1.6 dev eth0 STALE\n',
      ),
      'ip -6 neighbor show': _result(
        'fe80::1 dev eth0 lladdr AA:BB:CC:DD:EE:21 router REACHABLE\n'
        '2001:db8::2 dev eth0 lladdr AA:BB:CC:DD:EE:22 STALE\n',
      ),
    });
    final tools = NetworkNeighborTools(platform: NetworkNeighborPlatform.linux);

    final result = _decode(
      await tools.arp(ipVersion: ' IPV4 ', processRunner: runner.call),
    );
    final entries = _entries(result);

    expect(runner.calls, ['ip neighbor show']);
    expect(result['ip_version'], 'ipv4');
    expect(entries.map((entry) => entry['ip']), [
      '192.168.1.2',
      '192.168.1.10',
    ]);
    expect(entries.first['state'], 'REACHABLE');
    expect(entries.last['source'], 'arp');

    final ndp = _decode(await tools.ndp(processRunner: runner.call));
    final ndpEntries = _entries(ndp);
    expect(runner.calls.last, 'ip -6 neighbor show');
    expect(ndp['ip_version'], 'ipv6');
    expect(ndpEntries, hasLength(2));
    expect(ndpEntries.first['source'], 'ndp');
    expect(ndpEntries.last['state'], 'REACHABLE');
  });

  test(
    'invalid versions and unsupported platforms fail before commands',
    () async {
      final runner = _FakeProcessRunner({});
      final linuxTools = NetworkNeighborTools(
        platform: NetworkNeighborPlatform.linux,
      );

      final invalid = _decode(
        await linuxTools.arp(ipVersion: 'ipx', processRunner: runner.call),
      );
      expect(invalid, {
        'error': true,
        'message': 'ip_version must be one of: all, ipv4, ipv6',
      });

      final unsupportedTools = NetworkNeighborTools(
        platform: NetworkNeighborPlatform.unsupported,
      );
      final unsupported = _decode(
        await unsupportedTools.arp(processRunner: runner.call),
      );
      expect(unsupported, {
        'error': true,
        'message':
            'ARP inspection is only supported on macOS and Linux. '
            'This platform does not expose a compatible local neighbor table.',
      });
      expect(runner.calls, isEmpty);
    },
  );

  test('non-zero process results contribute no entries', () async {
    final runner = _FakeProcessRunner({
      'ip neighbor show': _result('', exitCode: 1),
      'ip -6 neighbor show': _result('', exitCode: 2),
    });
    final tools = NetworkNeighborTools(platform: NetworkNeighborPlatform.linux);

    final result = _decode(await tools.arp(processRunner: runner.call));

    expect(result['entries_found'], 0);
    expect(_entries(result), isEmpty);
    expect(runner.calls, ['ip neighbor show', 'ip -6 neighbor show']);
  });

  test('address utilities preserve zones, family order, and fallback', () {
    expect(normalizeNetworkIpForComparison('fe80::1%en0'), 'fe80::1');
    expect(
      compareNetworkIpAddresses('192.168.1.2', '192.168.1.10'),
      lessThan(0),
    );
    expect(
      compareNetworkIpAddresses('192.168.1.10', '2001:db8::1'),
      lessThan(0),
    );
    expect(compareNetworkIpAddresses('host-b', 'host-a'), greaterThan(0));
  });
}

ProcessResult _result(String stdout, {int exitCode = 0}) {
  return ProcessResult(1, exitCode, stdout, '');
}

Map<String, dynamic> _decode(String value) {
  return jsonDecode(value) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _entries(Map<String, dynamic> value) {
  return (value['entries'] as List<dynamic>).cast<Map<String, dynamic>>();
}

class _FakeProcessRunner {
  _FakeProcessRunner(this.results);

  final Map<String, ProcessResult> results;
  final List<String> calls = [];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    final key = '$executable ${arguments.join(' ')}';
    calls.add(key);
    final result = results[key];
    if (result == null) {
      throw StateError('Unexpected process call: $key');
    }
    return result;
  }
}
