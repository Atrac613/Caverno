import 'package:caverno/features/chat/data/datasources/built_in_network_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _OperationCall = ({String name, Map<String, dynamic> arguments});

void main() {
  group('BuiltInNetworkToolHandler', () {
    test('owns the exact ordered network family', () {
      final handler = BuiltInNetworkToolHandler(
        operationRunner: ({required name, required arguments}) async => '',
      );
      final definitionNames = handler.definitions
          .map(
            (tool) =>
                (tool['function']! as Map<String, dynamic>)['name']! as String,
          )
          .toList(growable: false);

      expect(definitionNames, BuiltInNetworkToolHandler.toolNames);
      for (final name in BuiltInNetworkToolHandler.toolNames) {
        expect(handler.handles(name), isTrue, reason: name);
      }
      expect(handler.handles('remote_network_tool'), isFalse);
    });

    test(
      'rejects missing required arguments without calling the runner',
      () async {
        final calls = <_OperationCall>[];
        final handler = BuiltInNetworkToolHandler(
          operationRunner: ({required name, required arguments}) async {
            calls.add((name: name, arguments: arguments));
            return 'unexpected';
          },
        );
        const cases = [
          ('ping', <String, dynamic>{}, 'Host is required'),
          ('ping6', <String, dynamic>{}, 'Host is required'),
          ('route_lookup', <String, dynamic>{}, 'Host is required'),
          ('whois_lookup', <String, dynamic>{}, 'Domain is required'),
          ('dns_lookup', <String, dynamic>{}, 'Host is required'),
          ('dns_query', <String, dynamic>{}, 'Target is required'),
          ('port_check', <String, dynamic>{}, 'Host and port are required'),
          ('ssl_certificate', <String, dynamic>{}, 'Host is required'),
          ('http_status', <String, dynamic>{}, 'URL is required'),
          ('http_get', <String, dynamic>{}, 'URL is required'),
          ('http_head', <String, dynamic>{}, 'URL is required'),
          ('http_post', <String, dynamic>{}, 'URL is required'),
          ('http_put', <String, dynamic>{}, 'URL is required'),
          ('http_patch', <String, dynamic>{}, 'URL is required'),
          ('http_delete', <String, dynamic>{}, 'URL is required'),
          ('traceroute', <String, dynamic>{}, 'Host is required'),
          ('path_mtu', <String, dynamic>{}, 'Host is required'),
        ];

        for (final testCase in cases) {
          final result = await handler.execute(
            name: testCase.$1,
            arguments: testCase.$2,
          );
          expect(result.toolName, testCase.$1);
          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, testCase.$3);
        }
        expect(calls, isEmpty);
      },
    );

    test(
      'normalizes every operation family before invoking the runner',
      () async {
        final calls = <_OperationCall>[];
        final handler = BuiltInNetworkToolHandler(
          operationRunner: ({required name, required arguments}) async {
            calls.add((
              name: name,
              arguments: Map<String, dynamic>.from(arguments),
            ));
            return '{"open":false}';
          },
        );
        final cases =
            <
              ({
                String name,
                Map<String, dynamic> arguments,
                Map<String, dynamic> normalized,
              })
            >[
              (
                name: 'ping',
                arguments: {'host': ' example.com ', 'count': 0, 'timeout': 99},
                normalized: {'host': 'example.com', 'count': 1, 'timeout': 30},
              ),
              (
                name: 'ping6',
                arguments: {'host': '2001:db8::1'},
                normalized: {'host': '2001:db8::1', 'count': 4, 'timeout': 5},
              ),
              (
                name: 'arp',
                arguments: {'host': ' ', 'ip_version': ' IPv6 '},
                normalized: {'host': null, 'ip_version': 'IPv6'},
              ),
              (
                name: 'ndp',
                arguments: {'host': ' fe80::1 '},
                normalized: {'host': 'fe80::1'},
              ),
              (
                name: 'route_lookup',
                arguments: {'host': ' example.com ', 'ip_version': ' IPv6 '},
                normalized: {'host': 'example.com', 'ip_version': 'ipv6'},
              ),
              (
                name: 'interface_info',
                arguments: {'interface': ' ', 'ip_version': ' IPv4 '},
                normalized: {'interface': null, 'ip_version': 'ipv4'},
              ),
              (
                name: 'whois_lookup',
                arguments: {'domain': ' example.com '},
                normalized: {'domain': 'example.com'},
              ),
              (
                name: 'dns_lookup',
                arguments: {'host': ' example.com '},
                normalized: {'host': 'example.com'},
              ),
              (
                name: 'dns_query',
                arguments: {'target': ' example.com ', 'record_type': ' aaaa '},
                normalized: {'target': 'example.com', 'record_type': 'AAAA'},
              ),
              (
                name: 'port_check',
                arguments: {'host': ' localhost ', 'port': 443.9, 'timeout': 0},
                normalized: {'host': 'localhost', 'port': 443, 'timeout': 1},
              ),
              (
                name: 'ssl_certificate',
                arguments: {'host': ' example.com ', 'port': 99999},
                normalized: {'host': 'example.com', 'port': 65535},
              ),
              (
                name: 'http_status',
                arguments: {'url': ' https://example.com ', 'timeout': 99},
                normalized: {'url': 'https://example.com', 'timeout': 30},
              ),
              for (final method in const [
                'http_get',
                'http_head',
                'http_post',
                'http_put',
                'http_patch',
                'http_delete',
              ])
                (
                  name: method,
                  arguments: {
                    'url': ' https://example.com/api ',
                    'headers': <dynamic, dynamic>{
                      1: 2,
                      'drop': null,
                      null: 'ignored',
                    },
                    'body': '{}',
                    'content_type': ' application/json ',
                    'timeout': 0,
                    'follow_redirects': false,
                    'max_redirects': 99,
                  },
                  normalized: {
                    'url': 'https://example.com/api',
                    'headers': {'1': '2'},
                    'body': '{}',
                    'content_type': 'application/json',
                    'timeout': 1,
                    'follow_redirects': false,
                    'max_redirects': 10,
                  },
                ),
              (
                name: 'traceroute',
                arguments: {
                  'host': ' example.com ',
                  'max_hops': 0,
                  'timeout': 99,
                },
                normalized: {
                  'host': 'example.com',
                  'max_hops': 1,
                  'timeout': 10,
                },
              ),
              (
                name: 'path_mtu',
                arguments: {'host': ' example.com ', 'ip_version': ' IPv6 '},
                normalized: {'host': 'example.com', 'ip_version': 'ipv6'},
              ),
              (
                name: 'mdns_browse',
                arguments: {
                  'service_type': ' ',
                  'ip_version': ' IPv4 ',
                  'timeout_ms': 100,
                  'max_results': 999,
                },
                normalized: {
                  'service_type': '_services._dns-sd._udp.local',
                  'ip_version': 'ipv4',
                  'timeout_ms': 200,
                  'max_results': 100,
                },
              ),
            ];

        for (final testCase in cases) {
          calls.clear();
          final result = await handler.execute(
            name: testCase.name,
            arguments: testCase.arguments,
          );
          expect(result.toolName, testCase.name);
          expect(result.result, '{"open":false}');
          expect(result.isSuccess, isTrue);
          expect(result.errorMessage, isNull);
          expect(calls, hasLength(1));
          expect(calls.single.name, testCase.name);
          expect(calls.single.arguments, testCase.normalized);
        }
      },
    );

    test('converts runner exceptions into unsuccessful tool results', () async {
      final handler = BuiltInNetworkToolHandler(
        operationRunner: ({required name, required arguments}) async {
          throw StateError('network runner failed');
        },
      );

      final result = await handler.execute(
        name: 'ping',
        arguments: const {'host': 'example.com'},
      );

      expect(result.toolName, 'ping');
      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Bad state: network runner failed');
    });

    test('rejects execution for an unknown operation', () async {
      final handler = BuiltInNetworkToolHandler(
        operationRunner: ({required name, required arguments}) async => '',
      );

      expect(
        () => handler.execute(name: 'remote_network_tool', arguments: const {}),
        throwsArgumentError,
      );
    });
  });

  test(
    'McpToolService delegates built-in network execution to the handler',
    () async {
      final calls = <_OperationCall>[];
      final handler = BuiltInNetworkToolHandler(
        operationRunner: ({required name, required arguments}) async {
          calls.add((name: name, arguments: arguments));
          return '{"reachable":true}';
        },
      );
      final service = McpToolService(networkToolHandler: handler);

      final result = await service.executeTool(
        name: 'ping',
        arguments: const {'host': ' example.com '},
      );

      expect(result.isSuccess, isTrue);
      expect(result.result, '{"reachable":true}');
      expect(calls, hasLength(1));
      expect(calls.single.name, 'ping');
      expect(calls.single.arguments, {
        'host': 'example.com',
        'count': 4,
        'timeout': 5,
      });
    },
  );
}
