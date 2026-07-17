import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/ble_service.dart';
import 'package:caverno/core/services/browser_session_service.dart';
import 'package:caverno/core/services/browser_tool_policy.dart';
import 'package:caverno/core/services/lan_scan_service.dart';
import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:caverno/core/services/serial_port_service.dart';
import 'package:caverno/core/services/ssh_service.dart';
import 'package:caverno/core/services/wifi_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/built_in_ble_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_browser_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_computer_use_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_lan_scan_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_serial_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_ssh_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_wifi_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_client.dart';
import 'package:caverno/features/chat/data/datasources/searxng_client.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _networkToolNames = [
  'ping',
  'ping6',
  'arp',
  'ndp',
  'route_lookup',
  'interface_info',
  'whois_lookup',
  'dns_lookup',
  'dns_query',
  'port_check',
  'ssl_certificate',
  'http_status',
  'http_get',
  'http_head',
  'http_post',
  'http_put',
  'http_patch',
  'http_delete',
  'traceroute',
  'path_mtu',
  'mdns_browse',
];

const _filesystemInspectionToolNames = [
  'list_directory',
  'read_file',
  'inspect_file',
  'find_files',
  'search_files',
];

const _filesystemMutationToolNames = [
  'write_file',
  'edit_file',
  'delete_file',
  'rollback_last_file_change',
];

const _filesystemToolNames = [
  ..._filesystemInspectionToolNames,
  ..._filesystemMutationToolNames,
];

const _localCommandToolNames = [
  'local_execute_command',
  'process_start',
  'process_status',
  'process_tail',
  'process_wait',
  'process_cancel',
  'process_list',
  'run_tests',
];

const _sshToolNames = ['ssh_connect', 'ssh_execute_command', 'ssh_disconnect'];

const _bleToolNames = BuiltInBleToolHandler.toolNames;
const _wifiToolNames = BuiltInWifiToolHandler.toolNames;
const _lanScanToolNames = BuiltInLanScanToolHandler.toolNames;
const _serialToolNames = BuiltInSerialToolHandler.toolNames;
const _computerUseToolNames = BuiltInComputerUseToolHandler.toolNames;
const _browserToolNames = BuiltInBrowserToolHandler.toolNames;

const _interceptedRemoteCollisionNames = [
  'spawn_subagent',
  'get_subagent_result',
  'save_skill',
];

const _prefixCollisionRemoteNames = [
  'browser_open',
  'browser_export_state',
  'computer_click',
  'computer_custom_action',
  'Browser_Mixed_Case',
  'COMPUTER_Mixed_Case',
];

String _openAiFunctionName(Map<String, dynamic> tool) =>
    (tool['function']! as Map<String, dynamic>)['name']! as String;

List<dynamic> _definitionRequired(Map<String, dynamic> tool) {
  final function = tool['function']! as Map<String, dynamic>;
  final parameters = function['parameters']! as Map<String, dynamic>;
  return parameters['required'] as List<dynamic>? ?? const <dynamic>[];
}

class _FakeBackgroundProcessTools extends BackgroundProcessTools {
  _FakeBackgroundProcessTools({
    required this.statusResults,
    this.startResult = '',
    this.tailResult,
    this.waitResult,
    this.cancelResult,
  });

  final Map<String, String> statusResults;
  final String startResult;
  final String? tailResult;
  final String? waitResult;
  final String? cancelResult;
  final List<Map<String, dynamic>> startCalls = [];

  @override
  Future<String> start({
    required String command,
    required String workingDirectory,
    String? label,
  }) async {
    startCalls.add({
      'command': command,
      'working_directory': workingDirectory,
      if (label != null && label.isNotEmpty) 'label': label,
    });
    return startResult.isNotEmpty
        ? startResult
        : jsonEncode({
            'ok': false,
            'code': 'start_not_configured',
            'error': 'No start result configured.',
          });
  }

  @override
  bool get isSupported => true;

  @override
  Future<String> status({required String jobId, int? tailChars}) async {
    return statusResults[jobId] ??
        jsonEncode({
          'ok': false,
          'code': 'job_not_found',
          'job_id': jobId,
          'error': 'No background process job exists for job_id: $jobId',
        });
  }

  @override
  Future<String> tail({required String jobId, int? maxChars}) async {
    return tailResult ??
        jsonEncode({
          'ok': false,
          'code': 'job_not_found',
          'job_id': jobId,
          'error': 'No background process job exists for job_id: $jobId',
        });
  }

  @override
  Future<String> wait({required String jobId, int? waitMs}) async {
    return waitResult ??
        jsonEncode({
          'ok': false,
          'code': 'job_not_found',
          'job_id': jobId,
          'error': 'No background process job exists for job_id: $jobId',
        });
  }

  @override
  Future<String> cancel({required String jobId}) async {
    return cancelResult ??
        jsonEncode({
          'ok': false,
          'code': 'job_not_found',
          'job_id': jobId,
          'error': 'No background process job exists for job_id: $jobId',
        });
  }
}

void main() {
  group('McpToolEntity.toOpenAiTool', () {
    test('sanitizes MCP server details in the tool description', () {
      const tool = McpToolEntity(
        name: 'remote_search',
        description: 'Search remote content',
        inputSchema: {'type': 'object'},
        sourceUrl: 'https://user:secret@example.com:8080/mcp?token=abc',
      );

      final openAiTool = tool.toOpenAiTool();
      final function = openAiTool['function']! as Map<String, dynamic>;
      final description = function['description']! as String;

      expect(openAiTool[McpToolEntity.openAiExternalToolKey], isTrue);
      expect(
        openAiTool[McpToolEntity.openAiSourceLabelKey],
        'example.com:8080',
      );
      expect(jsonEncode(openAiTool), isNot(contains('user:secret')));
      expect(jsonEncode(openAiTool), isNot(contains('token=abc')));
      expect(description, contains('example.com:8080'));
      expect(description, isNot(contains('secret')));
      expect(description, isNot(contains('token')));
      expect(description, isNot(contains('/mcp')));
    });
  });

  group('McpToolService', () {
    test('preserves the ordered built-in network tool definitions', () {
      final service = McpToolService();

      final definitions = service
          .getOpenAiToolDefinitions()
          .where(
            (tool) => _networkToolNames.contains(_openAiFunctionName(tool)),
          )
          .toList();

      expect(definitions.map(_openAiFunctionName), _networkToolNames);
      expect(
        sha256.convert(utf8.encode(jsonEncode(definitions))).toString(),
        'ecb762c734906fd33778e9e825cee4bd1c4990b4025c854823222620dce0ec9f',
      );

      final functionNames = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toList();
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        expect(functionNames, contains('os_get_system_info'));
        expect(functionNames, contains('run_tests'));
        expect(functionNames, contains('git_finish_worktree_session'));
      }
      if (Platform.isMacOS || Platform.isLinux) {
        expect(functionNames, contains('os_log_read'));
      }
    });

    test(
      'hides disabled network definitions but keeps direct validation routing',
      () async {
        final service = McpToolService(
          disabledBuiltInTools: _networkToolNames.toSet(),
        );

        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toSet();
        expect(functionNames.intersection(_networkToolNames.toSet()), isEmpty);

        final result = await service.executeTool(
          name: 'ping',
          arguments: const {},
        );
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'Host is required');
      },
    );

    test('preserves required network argument failures', () async {
      final service = McpToolService();
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
        final result = await service.executeTool(
          name: testCase.$1,
          arguments: testCase.$2,
        );
        expect(result.toolName, testCase.$1);
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, testCase.$3);
      }
    });

    test('preserves ordered SSH definitions and service placement', () {
      final unavailableNames = McpToolService()
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(unavailableNames.intersection(_sshToolNames.toSet()), isEmpty);

      final service = McpToolService(
        sshService: _FakeMcpSshService(),
        bleService: BleService(),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final sshDefinitions = definitions
          .where((tool) => _sshToolNames.contains(_openAiFunctionName(tool)))
          .toList();

      expect(sshDefinitions.map(_openAiFunctionName), _sshToolNames);
      final sshStart = names.indexOf(_sshToolNames.first);
      final sshEnd = names.indexOf(_sshToolNames.last);
      expect(sshStart, names.indexOf('git_finish_worktree_session') + 1);
      expect(names.indexOf(_bleToolNames.first), sshEnd + 1);
    });

    test('preserves SSH direct denial and disabled routing', () async {
      final ssh = _FakeMcpSshService();
      final service = McpToolService(
        sshService: ssh,
        disabledBuiltInTools: _sshToolNames.toSet(),
      );
      final names = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(names.intersection(_sshToolNames.toSet()), isEmpty);

      final connect = await service.executeTool(
        name: 'ssh_connect',
        arguments: const {'host': 'example.com'},
      );
      final disconnect = await service.executeTool(
        name: 'ssh_disconnect',
        arguments: const {},
      );

      expect(connect.isSuccess, isFalse);
      expect(
        connect.errorMessage,
        'ssh_connect must be handled by ChatNotifier (internal error)',
      );
      expect(disconnect.isSuccess, isTrue);
      expect(disconnect.result, 'No active SSH session');
      expect(ssh.disconnectCalls, 1);
    });

    test('preserves approved SSH command execution and validation', () async {
      final ssh = _FakeMcpSshService(
        connected: true,
        executionResult: SshExecutionResult(
          stdout: 'out\n',
          stderr: 'warn\n',
          exitCode: 7,
        ),
      );
      final service = McpToolService(sshService: ssh);

      final executed = await service.executeTool(
        name: 'ssh_execute_command',
        arguments: const {'command': '  printf output  ', 'reason': 'verify'},
      );
      final empty = await service.executeTool(
        name: 'ssh_execute_command',
        arguments: const {'command': '   '},
      );

      expect(executed.isSuccess, isTrue);
      expect(
        executed.result,
        'exit_code: 7\n--- stdout ---\nout\n\n--- stderr ---\nwarn\n\n',
      );
      expect(ssh.executedCommands, ['printf output']);
      expect(empty.isSuccess, isFalse);
      expect(empty.errorMessage, 'command is required');
      expect(ssh.executedCommands, hasLength(1));
    });

    test('preserves unavailable and inactive SSH results', () async {
      final unavailable = McpToolService();
      final inactiveSsh = _FakeMcpSshService();
      final inactive = McpToolService(sshService: inactiveSsh);

      final unavailableExecute = await unavailable.executeTool(
        name: 'ssh_execute_command',
        arguments: const {'command': 'pwd'},
      );
      final unavailableDisconnect = await unavailable.executeTool(
        name: 'ssh_disconnect',
        arguments: const {},
      );
      final inactiveExecute = await inactive.executeTool(
        name: 'ssh_execute_command',
        arguments: const {'command': 'pwd'},
      );

      expect(unavailableExecute.isSuccess, isFalse);
      expect(unavailableExecute.errorMessage, 'SSH service is unavailable');
      expect(unavailableDisconnect.isSuccess, isTrue);
      expect(unavailableDisconnect.result, 'No active SSH session');
      expect(inactiveExecute.isSuccess, isFalse);
      expect(
        inactiveExecute.errorMessage,
        'No active SSH session — call ssh_connect first',
      );
      expect(inactiveSsh.executedCommands, isEmpty);
    });

    test(
      'uses an injected SSH handler and retains the public service',
      () async {
        final publicSsh = _FakeMcpSshService();
        final handlerSsh = _FakeMcpSshService(
          connected: true,
          executionResult: SshExecutionResult(
            stdout: 'handler',
            stderr: '',
            exitCode: 0,
          ),
        );
        final service = McpToolService(
          sshService: publicSsh,
          sshToolHandler: BuiltInSshToolHandler(sshService: handlerSsh),
        );

        final result = await service.executeTool(
          name: 'ssh_execute_command',
          arguments: const {'command': 'whoami'},
        );

        expect(identical(service.sshService, publicSsh), isTrue);
        expect(result.isSuccess, isTrue);
        expect(result.result, 'exit_code: 0\n--- stdout ---\nhandler\n');
        expect(handlerSsh.executedCommands, ['whoami']);
        expect(publicSsh.executedCommands, isEmpty);
      },
    );

    test('preserves ordered BLE definitions and service placement', () {
      final unavailableNames = McpToolService()
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(unavailableNames.intersection(_bleToolNames.toSet()), isEmpty);

      final service = McpToolService(
        sshService: SshService(),
        bleService: BleService(),
        wifiService: WifiService(),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final bleDefinitions = definitions
          .where((tool) => _bleToolNames.contains(_openAiFunctionName(tool)))
          .toList();

      expect(bleDefinitions.map(_openAiFunctionName), _bleToolNames);
      final bleStart = names.indexOf(_bleToolNames.first);
      final bleEnd = names.indexOf(_bleToolNames.last);
      expect(bleStart, names.indexOf('ssh_disconnect') + 1);
      expect(names.indexOf('wifi_scan'), bleEnd + 1);
    });

    test('hides disabled BLE definitions but keeps direct routing', () async {
      final service = McpToolService(
        bleService: BleService(),
        disabledBuiltInTools: _bleToolNames.toSet(),
      );
      final names = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(names.intersection(_bleToolNames.toSet()), isEmpty);

      final result = await service.executeTool(
        name: 'ble_connect',
        arguments: const {'device_id': 'device'},
      );
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'ble_connect must be handled by ChatNotifier (internal error)',
      );
    });

    test('preserves ordered WiFi definitions and service placement', () {
      final unavailableNames = McpToolService()
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(unavailableNames.intersection(_wifiToolNames.toSet()), isEmpty);

      final service = McpToolService(
        bleService: BleService(),
        wifiService: _FakeMcpWifiService(),
        lanScanService: LanScanService(),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final wifiDefinitions = definitions
          .where((tool) => _wifiToolNames.contains(_openAiFunctionName(tool)))
          .toList();

      expect(wifiDefinitions.map(_openAiFunctionName), _wifiToolNames);
      final wifiStart = names.indexOf(_wifiToolNames.first);
      final wifiEnd = names.indexOf(_wifiToolNames.last);
      expect(wifiStart, names.indexOf(_bleToolNames.last) + 1);
      expect(names.indexOf('lan_scan'), wifiEnd + 1);
    });

    test('hides disabled WiFi definitions but keeps direct routing', () async {
      final wifi = _FakeMcpWifiService(cachedResult: 'cached:ssid');
      final service = McpToolService(
        wifiService: wifi,
        disabledBuiltInTools: _wifiToolNames.toSet(),
      );
      final names = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(names.intersection(_wifiToolNames.toSet()), isEmpty);

      final result = await service.executeTool(
        name: 'wifi_get_scan_results',
        arguments: const {'sort_by': 'ssid'},
      );
      expect(result.isSuccess, isTrue);
      expect(result.result, 'cached:ssid');
      expect(wifi.scanResultSorts, ['ssid']);
    });

    test('preserves ordered LAN scan definitions and service placement', () {
      final unavailableNames = McpToolService()
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(unavailableNames.intersection(_lanScanToolNames.toSet()), isEmpty);

      final service = McpToolService(
        wifiService: _FakeMcpWifiService(),
        lanScanService: _FakeMcpLanScanService(),
        serialPortService: SerialPortService(),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final lanDefinitions = definitions
          .where(
            (tool) => _lanScanToolNames.contains(_openAiFunctionName(tool)),
          )
          .toList();

      expect(lanDefinitions.map(_openAiFunctionName), _lanScanToolNames);
      final lanStart = names.indexOf(_lanScanToolNames.first);
      final lanEnd = names.indexOf(_lanScanToolNames.last);
      expect(lanStart, names.indexOf(_wifiToolNames.last) + 1);
      if (SerialPortService.isSupported) {
        expect(names.indexOf('serial_list_ports'), lanEnd + 1);
      }
    });

    test('preserves LAN scan argument conversion and result bytes', () async {
      final lanScan = _FakeMcpLanScanService(scanResult: '{"hosts_found":1}\n');
      final service = McpToolService(lanScanService: lanScan);

      final result = await service.executeTool(
        name: 'lan_scan',
        arguments: const {
          'subnet': ' 192.0.2.0/30 ',
          'ip_version': ' ipv4 ',
          'timeout': 250.9,
          'ports': [443.8, 22],
        },
      );

      expect(result.toolName, 'lan_scan');
      expect(result.result, '{"hosts_found":1}\n');
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(lanScan.scanCalls, [
        {
          'subnet': '192.0.2.0/30',
          'ip_version': 'ipv4',
          'timeout_ms': 250,
          'ports': [443, 22],
        },
      ]);
    });

    test('hides disabled LAN definitions but keeps direct routing', () async {
      final lanScan = _FakeMcpLanScanService(cachedResult: 'cached:hostname');
      final service = McpToolService(
        lanScanService: lanScan,
        disabledBuiltInTools: _lanScanToolNames.toSet(),
      );
      final names = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(names.intersection(_lanScanToolNames.toSet()), isEmpty);

      final result = await service.executeTool(
        name: 'lan_get_scan_results',
        arguments: const {'sort_by': 'hostname'},
      );
      expect(result.isSuccess, isTrue);
      expect(result.result, 'cached:hostname');
      expect(lanScan.scanResultSorts, ['hostname']);
    });

    test('preserves ordered serial definitions and service placement', () {
      final unavailableNames = McpToolService()
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(unavailableNames.intersection(_serialToolNames.toSet()), isEmpty);

      final service = McpToolService(
        lanScanService: _FakeMcpLanScanService(),
        serialPortService: _FakeMcpSerialPortService(),
        computerUseService: _FakeMacosComputerUseService(),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final serialDefinitions = definitions
          .where((tool) => _serialToolNames.contains(_openAiFunctionName(tool)))
          .toList();

      if (SerialPortService.isSupported) {
        expect(serialDefinitions.map(_openAiFunctionName), _serialToolNames);
        final serialStart = names.indexOf(_serialToolNames.first);
        final serialEnd = names.indexOf(_serialToolNames.last);
        expect(serialStart, names.indexOf(_lanScanToolNames.last) + 1);
        expect(names.indexOf('computer_get_permissions'), serialEnd + 1);
      } else {
        expect(serialDefinitions, isEmpty);
      }
    });

    test('preserves serial direct denial and disabled routing', () async {
      final serial = _FakeMcpSerialPortService(listResult: 'serial:list');
      final service = McpToolService(
        serialPortService: serial,
        disabledBuiltInTools: _serialToolNames.toSet(),
      );
      final names = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(names.intersection(_serialToolNames.toSet()), isEmpty);

      final listResult = await service.executeTool(
        name: 'serial_list_ports',
        arguments: const {},
      );
      final openResult = await service.executeTool(
        name: 'serial_open',
        arguments: const {'port': '/dev/cu.example'},
      );

      expect(listResult.result, 'serial:list');
      expect(listResult.isSuccess, isTrue);
      expect(serial.listCalls, 1);
      expect(openResult.isSuccess, isFalse);
      expect(
        openResult.errorMessage,
        'Serial tool serial_open must be invoked with user approval and '
        'cannot be executed directly.',
      );
    });

    test(
      'hides unsupported serial definitions but keeps direct routing',
      () async {
        final serial = _FakeMcpSerialPortService(
          listResult: 'serial:unsupported',
        );
        final service = McpToolService(
          serialPortService: serial,
          serialToolHandler: BuiltInSerialToolHandler(
            serialPortService: serial,
            platformSupport: () => false,
          ),
        );
        final names = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toSet();

        final result = await service.executeTool(
          name: 'serial_list_ports',
          arguments: const {},
        );

        expect(names.intersection(_serialToolNames.toSet()), isEmpty);
        expect(result.result, 'serial:unsupported');
        expect(result.isSuccess, isTrue);
        expect(serial.listCalls, 1);
      },
    );

    test(
      'preserves serial direct argument conversion and result bytes',
      () async {
        final serial = _FakeMcpSerialPortService(
          readResult: 'serial:read\n',
          decodeResult: 'serial:decode',
          writeResult: 'serial:write',
          closeResult: 'serial:close',
        );
        final service = McpToolService(serialPortService: serial);

        final read = await service.executeTool(
          name: 'serial_read',
          arguments: const {
            'port': ' /dev/cu.read ',
            'encoding': 'hexdump',
            'max_bytes': 10.9,
            'clear': false,
            'frame_delimiter': '0d0a',
            'frame_length': 8.7,
            'max_frames': 4.8,
            'include_stats': true,
          },
        );
        final decode = await service.executeTool(
          name: 'serial_decode',
          arguments: const {
            'data': '01 02',
            'port': ' /dev/cu.decode ',
            'format': '<2B',
            'fields': ['first', 2],
            'consume': true,
          },
        );
        final write = await service.executeTool(
          name: 'serial_write',
          arguments: const {
            'port': ' /dev/cu.write ',
            'data': '41',
            'encoding': 'hex',
          },
        );
        final close = await service.executeTool(
          name: 'serial_close',
          arguments: const {'port': ' /dev/cu.close '},
        );

        expect(read.result, 'serial:read\n');
        expect(decode.result, 'serial:decode');
        expect(write.result, 'serial:write');
        expect(close.result, 'serial:close');
        expect(
          [read, decode, write, close].every((result) => result.isSuccess),
          isTrue,
        );
        expect(serial.readCalls, [
          {
            'port': '/dev/cu.read',
            'encoding': 'hexdump',
            'max_bytes': 10,
            'clear': false,
            'frame_delimiter_hex': '0d0a',
            'frame_length': 8,
            'max_frames': 4,
            'include_stats': true,
          },
        ]);
        expect(serial.decodeCalls, [
          {
            'data_hex': '01 02',
            'port': '/dev/cu.decode',
            'format': '<2B',
            'fields': ['first', '2'],
            'consume': true,
          },
        ]);
        expect(serial.writeCalls, [
          {'port': '/dev/cu.write', 'data': '41', 'encoding': 'hex'},
        ]);
        expect(serial.closeCalls, ['/dev/cu.close']);
      },
    );

    test('preserves ordered browser definitions and service placement', () {
      final unavailableNames = McpToolService()
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(unavailableNames.intersection(_browserToolNames.toSet()), isEmpty);

      final service = McpToolService(
        computerUseService: _FakeMacosComputerUseService(),
        browserService: _FakeMcpBrowserSessionService(),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final browserDefinitions = definitions
          .where(
            (tool) => _browserToolNames.contains(_openAiFunctionName(tool)),
          )
          .toList();

      expect(BrowserToolPolicy.allTools, _browserToolNames.toSet());
      expect(browserDefinitions.map(_openAiFunctionName), _browserToolNames);
      final browserStart = names.indexOf(_browserToolNames.first);
      final browserEnd = names.indexOf(_browserToolNames.last);
      expect(
        browserStart,
        names.indexOf('computer_stop_system_audio_recording') + 1,
      );
      expect(names.indexOf('tool_search'), 0);
      expect(browserEnd, names.length - 1);

      expect(_definitionRequired(browserDefinitions[0]), ['url']);
      expect(_definitionRequired(browserDefinitions[7]), ['value']);
      expect(_definitionRequired(browserDefinitions[10]), ['script']);
      expect(_definitionRequired(browserDefinitions[11]), ['filename', 'data']);
    });

    test(
      'hides disabled browser definitions but keeps direct routing',
      () async {
        final browser = _FakeMcpBrowserSessionService();
        final service = McpToolService(
          browserService: browser,
          disabledBuiltInTools: _browserToolNames.toSet(),
        );
        final names = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toSet();
        expect(names.intersection(_browserToolNames.toSet()), isEmpty);

        final result = await service.executeTool(
          name: 'browser_get_content',
          arguments: const {},
        );

        expect(result.isSuccess, isTrue);
        expect(result.result, '{"ok":true,"tool":"browser_get_content"}');
        expect(browser.calls.map((call) => call.name), ['browser_get_content']);
        expect(browser.calls.single.arguments, {
          'format': 'text',
          'max_chars': null,
        });
      },
    );

    test(
      'uses an injected browser handler independently of the service',
      () async {
        final browser = _FakeMcpBrowserSessionService();
        final handler = BuiltInBrowserToolHandler(browserService: browser);
        final service = McpToolService(browserToolHandler: handler);

        final result = await service.executeTool(
          name: 'browser_snapshot',
          arguments: const {'max_elements': 9},
        );

        expect(service.browserService, isNull);
        expect(service.browserToolHandler, same(handler));
        expect(result.isSuccess, isTrue);
        expect(browser.calls.single.name, 'browser_snapshot');
        expect(browser.calls.single.arguments, {'max_elements': 9});
        expect(
          service.getOpenAiToolDefinitions().map(_openAiFunctionName),
          contains('browser_snapshot'),
        );
      },
    );

    test('preserves every browser argument conversion and default', () async {
      final browser = _FakeMcpBrowserSessionService();
      final service = McpToolService(browserService: browser);

      final results = <McpToolResult>[
        await service.executeTool(
          name: 'browser_open',
          arguments: const {'url': 'https://example.com', 'reason': 'inspect'},
        ),
        await service.executeTool(
          name: 'browser_snapshot',
          arguments: const {'max_elements': 12.9},
        ),
        await service.executeTool(
          name: 'browser_get_content',
          arguments: const {'format': 'html', 'max_chars': 45.8},
        ),
        await service.executeTool(
          name: 'browser_screenshot',
          arguments: const {},
        ),
        await service.executeTool(
          name: 'browser_wait',
          arguments: const {'selector': '  #ready  ', 'timeout_ms': 250.7},
        ),
        await service.executeTool(
          name: 'browser_navigate_history',
          arguments: const {},
        ),
        await service.executeTool(name: 'browser_close', arguments: const {}),
        await service.executeTool(
          name: 'browser_fill',
          arguments: const {
            'ref': '12',
            'selector': '   ',
            'value': 'secret',
            'reason': 'fill',
          },
        ),
        await service.executeTool(
          name: 'browser_click',
          arguments: const {'ref': 4.9, 'selector': '  button.submit  '},
        ),
        await service.executeTool(
          name: 'browser_submit',
          arguments: const {'selector': '  form.search  '},
        ),
        await service.executeTool(
          name: 'browser_eval',
          arguments: const {'script': 'return document.title'},
        ),
        await service.executeTool(
          name: 'browser_save_data',
          arguments: const {},
        ),
      ];

      expect(results.every((result) => result.isSuccess), isTrue);
      expect(
        results.map((result) => result.result),
        _browserToolNames.map((name) => jsonEncode({'ok': true, 'tool': name})),
      );
      expect(browser.calls.map((call) => call.name), _browserToolNames);
      expect(browser.calls.map((call) => call.arguments), [
        <String, dynamic>{'url': 'https://example.com'},
        <String, dynamic>{'max_elements': 12},
        <String, dynamic>{'format': 'html', 'max_chars': 45},
        <String, dynamic>{},
        <String, dynamic>{'selector': '#ready', 'timeout_ms': 250},
        <String, dynamic>{'direction': 'reload'},
        <String, dynamic>{},
        <String, dynamic>{'ref': 12, 'selector': null, 'value': 'secret'},
        <String, dynamic>{'ref': 4, 'selector': 'button.submit'},
        <String, dynamic>{'selector': 'form.search'},
        <String, dynamic>{'script': 'return document.title'},
        <String, dynamic>{
          'filename': 'browser_data',
          'data': '',
          'format': 'json',
          'destination': null,
        },
      ]);
    });

    test('preserves browser failure and unknown-prefix results', () async {
      const failedPayload = '{"ok":false,"error":"page failed"}';
      final browser = _FakeMcpBrowserSessionService(
        results: const {'browser_open': failedPayload},
      );
      final available = McpToolService(browserService: browser);
      final unavailable = McpToolService();

      final failed = await available.executeTool(
        name: 'browser_open',
        arguments: const {'url': 'https://example.com'},
      );
      final unknown = await available.executeTool(
        name: 'browser_export_state',
        arguments: const {},
      );
      final unavailableUnknown = await unavailable.executeTool(
        name: 'browser_export_state',
        arguments: const {},
      );

      expect(failed.result, failedPayload);
      expect(failed.isSuccess, isFalse);
      expect(failed.errorMessage, 'page failed');
      expect(unknown.isSuccess, isFalse);
      expect(jsonDecode(unknown.result), {
        'ok': false,
        'code': 'tool_not_available',
        'error': 'No matching browser tool is available: browser_export_state',
      });
      expect(
        unknown.errorMessage,
        'No matching browser tool is available: browser_export_state',
      );
      expect(unavailableUnknown.result, isEmpty);
      expect(unavailableUnknown.isSuccess, isFalse);
      expect(
        unavailableUnknown.errorMessage,
        'Built-in browser tools are unavailable',
      );
    });

    test('preserves ordered built-in filesystem definitions and placement', () {
      final service = McpToolService();
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final inspectionDefinitions = definitions
          .where(
            (tool) => _filesystemInspectionToolNames.contains(
              _openAiFunctionName(tool),
            ),
          )
          .toList();
      final mutationDefinitions = definitions
          .where(
            (tool) => _filesystemMutationToolNames.contains(
              _openAiFunctionName(tool),
            ),
          )
          .toList();

      expect(
        inspectionDefinitions.map(_openAiFunctionName),
        _filesystemInspectionToolNames,
      );
      expect(
        sha256
            .convert(utf8.encode(jsonEncode(inspectionDefinitions)))
            .toString(),
        'e43cff1a45c1c8ba66c3aaae892dd5ad421a86e77b2c72ac72d98291df5cf15c',
      );
      if (FilesystemTools.isDesktopPlatform) {
        expect(
          mutationDefinitions.map(_openAiFunctionName),
          _filesystemMutationToolNames,
        );
        expect(
          sha256
              .convert(utf8.encode(jsonEncode(mutationDefinitions)))
              .toString(),
          '913d9ba8adc55f1d494fcb61b6cce8a7a319f7ba93d0585b9c20f28e2fad2097',
        );
      } else {
        expect(mutationDefinitions, isEmpty);
      }

      final inspectionStart = names.indexOf(
        _filesystemInspectionToolNames.first,
      );
      expect(
        names.sublist(
          inspectionStart,
          inspectionStart + _filesystemInspectionToolNames.length,
        ),
        _filesystemInspectionToolNames,
      );
      final dependencyIndex = names.indexOf('resolve_installed_dependency');
      final lspIndex = names.indexOf('lsp_go_to_definition');
      expect(dependencyIndex, inspectionStart + 5);
      expect(lspIndex, dependencyIndex + 1);
      if (FilesystemTools.isDesktopPlatform) {
        expect(names[lspIndex + 1], _filesystemMutationToolNames.first);
      }
    });

    test(
      'hides disabled filesystem definitions but keeps direct validation routing',
      () async {
        final service = McpToolService(
          disabledBuiltInTools: _filesystemToolNames.toSet(),
        );

        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toSet();
        expect(
          functionNames.intersection(_filesystemToolNames.toSet()),
          isEmpty,
        );

        const cases = [
          ('list_directory', <String, dynamic>{}, 'path is required'),
          ('read_file', <String, dynamic>{}, 'path is required'),
          ('inspect_file', <String, dynamic>{}, 'path is required'),
          ('write_file', <String, dynamic>{}, 'path is required'),
          ('edit_file', <String, dynamic>{}, 'path is required'),
          ('delete_file', <String, dynamic>{}, 'path is required'),
          ('find_files', <String, dynamic>{}, 'path and pattern are required'),
          ('search_files', <String, dynamic>{}, 'path and query are required'),
          (
            'rollback_last_file_change',
            <String, dynamic>{},
            'No recent file change is available to roll back',
          ),
        ];

        for (final testCase in cases) {
          final result = await service.executeTool(
            name: testCase.$1,
            arguments: testCase.$2,
          );
          expect(result.toolName, testCase.$1);
          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, testCase.$3);
        }
      },
    );

    test('preserves legacy filesystem payload success envelopes', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mcp_tool_service_filesystem_envelope_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final missingPath = '${tempDir.path}/missing';
      final service = McpToolService();

      final inspectionCalls = [
        ('list_directory', <String, dynamic>{'path': missingPath}),
        ('read_file', <String, dynamic>{'path': missingPath}),
        ('inspect_file', <String, dynamic>{'path': missingPath}),
        (
          'find_files',
          <String, dynamic>{'path': missingPath, 'pattern': '*.dart'},
        ),
        (
          'search_files',
          <String, dynamic>{'path': missingPath, 'query': 'needle'},
        ),
      ];
      for (final call in inspectionCalls) {
        final result = await service.executeTool(
          name: call.$1,
          arguments: call.$2,
        );
        expect(result.isSuccess, isTrue, reason: call.$1);
        expect(jsonDecode(result.result), contains('error'));
      }

      final writeResult = await service.executeTool(
        name: 'write_file',
        arguments: {'path': tempDir.path, 'content': 'not writable'},
      );
      expect(writeResult.isSuccess, isTrue);
      expect(jsonDecode(writeResult.result), contains('error'));

      final editable = File('${tempDir.path}/editable.txt')
        ..writeAsStringSync('current content\n');
      final editResult = await service.executeTool(
        name: 'edit_file',
        arguments: {
          'path': editable.path,
          'old_text': 'missing content',
          'new_text': 'replacement',
        },
      );
      expect(editResult.isSuccess, isTrue);
      expect(jsonDecode(editResult.result), contains('error'));

      final alreadyAppliedResult = await service.executeTool(
        name: 'edit_file',
        arguments: {
          'path': editable.path,
          'old_text': 'current',
          'new_text': 'current content',
        },
      );
      expect(alreadyAppliedResult.isSuccess, isTrue);
      expect(
        (jsonDecode(alreadyAppliedResult.result)
            as Map<String, dynamic>)['already_applied'],
        isTrue,
      );

      final deleteResult = await service.executeTool(
        name: 'delete_file',
        arguments: {'path': missingPath},
      );
      expect(deleteResult.isSuccess, isFalse);
      expect(deleteResult.errorMessage, 'Failed to delete file');
      expect(jsonDecode(deleteResult.result), contains('error'));
      expect(await service.previewLastFileRollbackChange(), isNull);
    });

    test('includes LSP go-to-definition tool definition', () {
      final service = McpToolService();

      final lspTool =
          service.getOpenAiToolDefinitions().firstWhere(
                (tool) =>
                    (tool['function']! as Map<String, dynamic>)['name'] ==
                    'lsp_go_to_definition',
              )['function']!
              as Map<String, dynamic>;
      final parameters = lspTool['parameters']! as Map<String, dynamic>;
      final properties = parameters['properties']! as Map<String, dynamic>;

      expect(lspTool['description'], contains('language server'));
      expect(properties, contains('path'));
      expect(properties, contains('line'));
      expect(properties, contains('column'));
      expect(parameters['required'], ['path', 'line', 'column']);
    });

    test('preserves ordered local command definitions and placement', () {
      final service = McpToolService(
        backgroundProcessTools: _FakeBackgroundProcessTools(
          statusResults: const {},
        ),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final localCommandDefinitions = definitions
          .where(
            (tool) =>
                _localCommandToolNames.contains(_openAiFunctionName(tool)),
          )
          .toList();

      if (!LocalShellTools.isDesktopPlatform) {
        expect(localCommandDefinitions, isEmpty);
        return;
      }

      expect(
        localCommandDefinitions.map(_openAiFunctionName),
        _localCommandToolNames,
      );
      expect(
        sha256
            .convert(utf8.encode(jsonEncode(localCommandDefinitions)))
            .toString(),
        '51b7845c3a6e82fb09864eb00debfad4c480f80dabd857f09dff9d36a0fb89b1',
      );

      final localCommandStart = names.indexOf(_localCommandToolNames.first);
      expect(
        names.sublist(
          localCommandStart,
          localCommandStart + _localCommandToolNames.length,
        ),
        _localCommandToolNames,
      );
      expect(names[localCommandStart - 1], _filesystemMutationToolNames.last);
      expect(
        names[localCommandStart + _localCommandToolNames.length],
        'os_get_system_info',
      );
    });

    test('hides process definitions without background capability', () {
      final service = McpToolService();
      final names = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .where(_localCommandToolNames.contains)
          .toList();

      expect(
        names,
        LocalShellTools.isDesktopPlatform
            ? const ['local_execute_command', 'run_tests']
            : isEmpty,
      );
    });

    test(
      'hides disabled local command definitions but keeps direct routing',
      () async {
        final service = McpToolService(
          disabledBuiltInTools: _localCommandToolNames.toSet(),
        );
        final names = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toSet();
        expect(names.intersection(_localCommandToolNames.toSet()), isEmpty);

        const requiredArgumentCases = [
          (
            'local_execute_command',
            <String, dynamic>{},
            'command and working_directory are required',
          ),
          (
            'process_start',
            <String, dynamic>{},
            'command and working_directory are required',
          ),
          ('process_status', <String, dynamic>{}, 'job_id is required'),
          ('process_tail', <String, dynamic>{}, 'job_id is required'),
          ('process_wait', <String, dynamic>{}, 'job_id is required'),
          ('process_cancel', <String, dynamic>{}, 'job_id is required'),
        ];

        for (final testCase in requiredArgumentCases) {
          final result = await service.executeTool(
            name: testCase.$1,
            arguments: testCase.$2,
          );
          expect(result.toolName, testCase.$1);
          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, testCase.$3);
        }

        final processList = await service.executeTool(
          name: 'process_list',
          arguments: const {},
        );
        expect(processList.toolName, 'process_list');
        expect(processList.isSuccess, isFalse);
        expect(
          jsonDecode(processList.result),
          equals({
            'ok': false,
            'code': 'background_process_monitor_unavailable',
            'error': 'Background process monitor is not available',
          }),
        );

        final runTests = await service.executeTool(
          name: 'run_tests',
          arguments: const {},
        );
        expect(runTests.toolName, 'run_tests');
        expect(runTests.isSuccess, isFalse);
        expect(
          runTests.result,
          '{"error":"run_tests must be executed through the chat command approval flow.","code":"approval_required"}',
        );
        expect(
          runTests.errorMessage,
          'run_tests must be executed through the chat command approval flow',
        );
      },
    );

    test('preserves local command unavailable result envelopes', () async {
      final service = McpToolService();
      final expectedToolsUnavailable = {
        'ok': false,
        'code': 'background_process_tools_unavailable',
        'error': 'Background process tools are not available',
      };

      for (final background in [true, 1, -1, 'true', '1', 'YES']) {
        final result = await service.executeTool(
          name: 'local_execute_command',
          arguments: {
            'command': 'sleep 30',
            'working_directory': '/tmp/project',
            'background': background,
          },
        );
        expect(result.isSuccess, isFalse, reason: '$background');
        expect(jsonDecode(result.result), expectedToolsUnavailable);
        expect(
          result.errorMessage,
          'Background process tools are not available',
        );
      }

      final processStart = await service.executeTool(
        name: 'process_start',
        arguments: const {
          'command': 'sleep 30',
          'working_directory': '/tmp/project',
        },
      );
      expect(processStart.result, isEmpty);
      expect(processStart.isSuccess, isFalse);
      expect(
        processStart.errorMessage,
        'Background process tools are not available',
      );

      for (final name in const [
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
      ]) {
        final result = await service.executeTool(
          name: name,
          arguments: const {'job_id': 'missing'},
        );
        expect(result.isSuccess, isFalse, reason: name);
        expect(jsonDecode(result.result), expectedToolsUnavailable);
        expect(
          result.errorMessage,
          'Background process tools are not available',
        );
      }
    });

    test('preserves legacy local command payload success envelopes', () async {
      const providerFailure =
          '{"ok":false,"code":"synthetic_provider_failure"}';
      final fakeTools = _FakeBackgroundProcessTools(
        statusResults: const {'job': providerFailure},
        startResult: providerFailure,
        tailResult: providerFailure,
        waitResult: providerFailure,
        cancelResult: providerFailure,
      );
      final service = McpToolService(backgroundProcessTools: fakeTools);
      final missingDirectory = await Directory.systemTemp.createTemp(
        'mcp_tool_service_missing_command_directory_',
      );
      final missingDirectoryPath = missingDirectory.path;
      await missingDirectory.delete();

      final foreground = await service.executeTool(
        name: 'local_execute_command',
        arguments: {
          'command': 'echo unreachable',
          'working_directory': missingDirectoryPath,
        },
      );
      expect(foreground.isSuccess, isTrue);
      expect(jsonDecode(foreground.result), contains('error'));

      final providerCalls = [
        (
          'local_execute_command',
          <String, dynamic>{
            'command': 'sleep 30',
            'working_directory': '/tmp/project',
            'background': true,
          },
        ),
        (
          'process_start',
          <String, dynamic>{
            'command': 'sleep 30',
            'working_directory': '/tmp/project',
          },
        ),
        ('process_status', <String, dynamic>{'job_id': 'job'}),
        ('process_tail', <String, dynamic>{'job_id': 'job'}),
        ('process_wait', <String, dynamic>{'job_id': 'job'}),
        ('process_cancel', <String, dynamic>{'job_id': 'job'}),
      ];

      for (final call in providerCalls) {
        final result = await service.executeTool(
          name: call.$1,
          arguments: call.$2,
        );
        expect(result.result, providerFailure, reason: call.$1);
        expect(result.isSuccess, isTrue, reason: call.$1);
        expect(result.errorMessage, isNull, reason: call.$1);
      }
    });

    test('describes sequential local command batching', () {
      final service = McpToolService();
      final tool = service.getOpenAiToolDefinitions().firstWhere(
        (tool) =>
            (tool['function']! as Map<String, dynamic>)['name'] ==
            'local_execute_command',
      );
      final function = tool['function']! as Map<String, dynamic>;
      final parameters = function['parameters']! as Map<String, dynamic>;
      final properties = parameters['properties']! as Map<String, dynamic>;
      final command = properties['command']! as Map<String, dynamic>;

      expect(function['description'], contains('exact shell command'));
      expect(function['description'], contains('portable early exit'));
      expect(function['description'], contains('On POSIX'));
      expect(function['description'], contains('format, analyze, and test'));
      expect(command['description'], contains('multiline script'));
      expect(command['description'], contains('portable early exit'));
    });

    test('requires chat handler for LSP go-to-definition execution', () async {
      final service = McpToolService();

      final result = await service.executeTool(
        name: 'lsp_go_to_definition',
        arguments: const {'path': 'lib/main.dart', 'line': 1, 'column': 1},
      );

      expect(result.isSuccess, isFalse);
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload['code'], 'chat_handler_required');
    });

    test(
      'includes process_list when background process tools are supported',
      () {
        final service = McpToolService(
          backgroundProcessTools: _FakeBackgroundProcessTools(
            statusResults: {},
          ),
        );

        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(
              (tool) =>
                  (tool['function']! as Map<String, dynamic>)['name']!
                      as String,
            )
            .toList();

        expect(functionNames, contains('process_start'));
        expect(functionNames, contains('process_status'));
        expect(functionNames, contains('process_tail'));
        expect(functionNames, contains('process_wait'));
        expect(functionNames, contains('process_cancel'));
        expect(functionNames, contains('process_list'));
      },
    );

    test(
      'includes background args in local_execute_command tool definition',
      () {
        final service = McpToolService();
        final localExecute =
            service.getOpenAiToolDefinitions().firstWhere(
                  (tool) =>
                      (tool['function']! as Map<String, dynamic>)['name'] ==
                      'local_execute_command',
                )['function']!
                as Map<String, dynamic>;
        final parameters = localExecute['parameters']! as Map<String, dynamic>;
        final properties = parameters['properties']! as Map<String, dynamic>;

        expect(properties['background'], isNotNull);
        final backgroundProperty =
            properties['background']! as Map<String, dynamic>;
        final labelProperty = properties['label']! as Map<String, dynamic>;

        expect(backgroundProperty['type'], 'boolean');
        expect(labelProperty['type'], 'string');
      },
    );

    test('describes process tools for background local command jobs', () {
      final service = McpToolService(
        backgroundProcessTools: _FakeBackgroundProcessTools(
          statusResults: const {},
        ),
      );
      final functions = service
          .getOpenAiToolDefinitions()
          .map((tool) => tool['function']! as Map<String, dynamic>)
          .toList();
      String descriptionFor(String toolName) {
        final tool = functions.firstWhere(
          (item) => (item['name']! as String) == toolName,
          orElse: () => throw StateError('Missing tool: $toolName'),
        );
        return (tool['description']! as String);
      }

      expect(
        descriptionFor('process_status'),
        contains('process_start or background local_execute_command'),
      );
      expect(
        descriptionFor('process_tail'),
        contains('background local_execute_command'),
      );
      expect(descriptionFor('process_wait'), contains('background process'));
      expect(
        descriptionFor('process_wait'),
        contains('report concise progress'),
      );
      expect(
        descriptionFor('process_cancel'),
        contains('running background process'),
      );
      expect(
        descriptionFor('process_list'),
        contains('background local_execute_command'),
      );
    });

    test(
      'executes local_execute_command in background when requested',
      () async {
        final fakeTools = _FakeBackgroundProcessTools(
          statusResults: const {},
          startResult: jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': 'proc_local_1',
            'command': 'sleep 30',
            'working_directory': '/tmp/project',
            'label': 'long task',
          }),
        );
        final service = McpToolService(backgroundProcessTools: fakeTools);

        final result = await service.executeTool(
          name: 'local_execute_command',
          arguments: const {
            'command': 'sleep 30',
            'working_directory': '/tmp/project',
            'background': true,
            'label': 'long task',
          },
        );

        expect(result.isSuccess, isTrue);
        expect(fakeTools.startCalls, hasLength(1));
        expect(
          fakeTools.startCalls.single,
          equals({
            'command': 'sleep 30',
            'working_directory': '/tmp/project',
            'label': 'long task',
          }),
        );
        expect(jsonDecode(result.result), containsPair('status', 'running'));
      },
    );

    test('blocks direct git writes through local_execute_command', () async {
      final service = McpToolService();

      final result = await service.executeTool(
        name: 'local_execute_command',
        arguments: const {
          'command': 'git merge feature/python-hello-world-3',
          'working_directory': '/tmp',
        },
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Use git_execute_command for git write commands',
      );
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload['code'], 'local_shell_git_write_blocked');
      expect(payload['git_subcommand'], 'merge feature/python-hello-world-3');
    });

    test(
      'blocks direct git writes before background local command start',
      () async {
        final fakeTools = _FakeBackgroundProcessTools(statusResults: const {});
        final service = McpToolService(backgroundProcessTools: fakeTools);

        final result = await service.executeTool(
          name: 'local_execute_command',
          arguments: const {
            'command': 'git worktree remove /tmp/worktree',
            'working_directory': '/tmp',
            'background': true,
            'label': 'remove worktree',
          },
        );

        expect(result.isSuccess, isFalse);
        expect(fakeTools.startCalls, isEmpty);
        final payload = jsonDecode(result.result) as Map<String, dynamic>;
        expect(payload['code'], 'local_shell_git_write_blocked');
        expect(payload['git_subcommand'], 'worktree remove /tmp/worktree');
        expect(
          payload['required_action'],
          contains('git_finish_worktree_session'),
        );
      },
    );

    test('blocks direct git writes before process_start', () async {
      final fakeTools = _FakeBackgroundProcessTools(statusResults: const {});
      final service = McpToolService(backgroundProcessTools: fakeTools);

      final result = await service.executeTool(
        name: 'process_start',
        arguments: const {
          'command': 'git checkout main',
          'working_directory': '/tmp',
          'label': 'checkout main',
        },
      );

      expect(result.isSuccess, isFalse);
      expect(fakeTools.startCalls, isEmpty);
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload['code'], 'local_shell_git_write_blocked');
      expect(payload['git_subcommand'], 'checkout main');
    });

    test(
      'waits for a background local_execute_command process to complete',
      () async {
        if (!BackgroundProcessTools().isSupported) {
          return;
        }

        final workingDirectory = await Directory.systemTemp.createTemp(
          'mcp_tool_service_wait_test_',
        );
        addTearDown(() async {
          if (workingDirectory.existsSync()) {
            await workingDirectory.delete(recursive: true);
          }
        });

        final backgroundTools = BackgroundProcessTools();
        final monitorService = BackgroundProcessMonitorService(
          tools: backgroundTools,
        );
        addTearDown(() async {
          monitorService.dispose();
          await backgroundTools.dispose();
        });
        final service = McpToolService(
          backgroundProcessTools: backgroundTools,
          backgroundProcessMonitorService: monitorService,
        );

        final startResult = await service.executeTool(
          name: 'local_execute_command',
          arguments: {
            'command': 'echo done',
            'working_directory': workingDirectory.path,
            'background': true,
            'label': 'integration wait test',
          },
        );
        expect(startResult.isSuccess, isTrue);
        final startPayload =
            jsonDecode(startResult.result) as Map<String, dynamic>;
        expect(startPayload['ok'], isTrue);

        final jobId = startPayload['job_id'] as String;
        expect(jobId, isNotEmpty);

        late Map<String, dynamic> waitPayload;
        for (var i = 0; i < 5; i++) {
          final waitResult = await service.executeTool(
            name: 'process_wait',
            arguments: {'job_id': jobId},
          );
          expect(waitResult.isSuccess, isTrue);
          waitPayload = jsonDecode(waitResult.result) as Map<String, dynamic>;
          if (waitPayload['status'] == 'exited') {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(waitPayload['ok'], isTrue);
        expect(waitPayload['job_id'], jobId);
        expect(waitPayload['status'], 'exited');
        expect(waitPayload['exit_code'], 0);
      },
    );

    test(
      'returns unavailable when background local_execute_command tools are missing',
      () async {
        final service = McpToolService();
        final result = await service.executeTool(
          name: 'local_execute_command',
          arguments: const {
            'command': 'sleep 30',
            'working_directory': '/tmp/project',
            'background': true,
          },
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Background process tools are not available',
        );
      },
    );

    test('returns monitored process snapshots from process_list', () async {
      final fakeTools = _FakeBackgroundProcessTools(
        statusResults: const {
          'missing': '{"ok":false,"code":"job_not_found","job_id":"missing"}',
        },
      );
      final monitor = BackgroundProcessMonitorService(tools: fakeTools);
      final registeredRunning = monitor.registerProcessStartResult(
        result: jsonEncode({
          'ok': true,
          'status': 'running',
          'job_id': 'proc_running',
          'command': 'sleep 1',
          'working_directory': '/tmp',
        }),
        arguments: const {'command': 'sleep 1', 'working_directory': '/tmp'},
      );
      final registeredFinished = monitor.registerProcessStartResult(
        result: jsonEncode({
          'ok': true,
          'status': 'exited',
          'exit_code': 0,
          'job_id': 'proc_done',
          'command': 'printf done',
          'working_directory': '/tmp',
        }),
        arguments: const {
          'command': 'printf done',
          'working_directory': '/tmp',
        },
      );

      expect(registeredRunning, isNotNull);
      expect(registeredFinished, isNotNull);

      final service = McpToolService(
        backgroundProcessTools: fakeTools,
        backgroundProcessMonitorService: monitor,
      );

      final runningOnly = await service.executeTool(
        name: 'process_list',
        arguments: {'include_finished': false},
      );
      final runningPayload =
          jsonDecode(runningOnly.result) as Map<String, dynamic>;
      expect(runningOnly.isSuccess, isTrue);
      expect(runningPayload['ok'], isTrue);
      final runningJobs = runningPayload['jobs'] as List<dynamic>;
      expect(runningJobs, hasLength(1));
      expect(
        (runningJobs.single as Map<String, dynamic>)['job_id'],
        'proc_running',
      );

      final filtered = await service.executeTool(
        name: 'process_list',
        arguments: {
          'job_ids': ['proc_done'],
          'include_finished': true,
          'limit': 3,
        },
      );
      final filteredPayload =
          jsonDecode(filtered.result) as Map<String, dynamic>;
      expect(filteredPayload['ok'], isTrue);
      final filteredJobs = filteredPayload['jobs'] as List<dynamic>;
      expect(filteredJobs, hasLength(1));
      expect(
        (filteredJobs.single as Map<String, dynamic>)['job_id'],
        'proc_done',
      );
    });

    test('registers read-only file tools (incl. inspect_file) everywhere', () {
      final service = McpToolService();

      final functionNames = service
          .getOpenAiToolDefinitions()
          .map(
            (tool) =>
                (tool['function']! as Map<String, dynamic>)['name']! as String,
          )
          .toList();

      // Read-only file inspection must be available on every platform (no
      // desktop gate) so attached or referenced large files can be analyzed on
      // mobile too.
      expect(functionNames, contains('list_directory'));
      expect(functionNames, contains('read_file'));
      expect(functionNames, contains('inspect_file'));
      expect(functionNames, contains('find_files'));
      expect(functionNames, contains('search_files'));
      expect(functionNames, contains('resolve_installed_dependency'));
    });

    test(
      'executes resolve_installed_dependency against local lockfiles',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'mcp_tool_service_dependency_grounding_test_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });
        final packageRoot = Directory('${tempDir.path}/cache/locked_dep-1.0.0')
          ..createSync(recursive: true);
        File(
          '${packageRoot.path}/README.md',
        ).writeAsStringSync('Locked dependency documentation.');
        File('${packageRoot.path}/lib/locked_dep.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('class LockedApi {}\n');
        Directory('${tempDir.path}/.dart_tool').createSync();
        File(
          '${tempDir.path}/.dart_tool/package_config.json',
        ).writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': [
              {
                'name': 'locked_dep',
                'rootUri': packageRoot.uri.toString(),
                'packageUri': 'lib/',
              },
            ],
          }),
        );
        File('${tempDir.path}/pubspec.lock').writeAsStringSync('''
packages:
  locked_dep:
    dependency: transitive
    description:
      name: locked_dep
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');

        final service = McpToolService();
        final result = await service.executeTool(
          name: 'resolve_installed_dependency',
          arguments: {
            'project_path': tempDir.path,
            'ecosystem': 'dart',
            'package_name': 'locked_dep',
            'symbol': 'LockedApi',
          },
        );

        expect(result.isSuccess, isTrue);
        final decoded = jsonDecode(result.result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['offline_only'], isTrue);
        expect(
          (decoded['package'] as Map<String, dynamic>)['version'],
          '1.0.0',
        );
        expect(decoded['matches'], isNotEmpty);
      },
    );

    test('inspect_file returns an overview and clamps head/tail', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mcp_tool_service_inspect_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final filePath = '${tempDir.path}/sample.log';
      final sink = File(filePath).openWrite();
      for (var i = 1; i <= 300; i++) {
        sink.writeln('2026-06-05 12:00:00 INFO line $i');
      }
      await sink.close();

      final service = McpToolService();
      final result = await service.executeTool(
        name: 'inspect_file',
        arguments: {'path': filePath, 'head_lines': 999, 'tail_lines': 5},
      );

      expect(result.isSuccess, isTrue);
      final decoded = jsonDecode(result.result) as Map<String, dynamic>;
      expect(decoded['total_lines'], 300);
      expect(decoded['format_hint'], 'log');
      expect((decoded['head'] as List).length, 100); // clamped from 999
      expect((decoded['tail'] as List).length, 5);
    });

    test('requires chat approval flow for run_tests execution', () async {
      final service = McpToolService();

      final result = await service.executeTool(
        name: 'run_tests',
        arguments: const {'test_path': 'test/widget_test.dart'},
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('chat command approval flow'));
      expect(result.result, contains('"code":"approval_required"'));
    });

    test(
      'describes run_tests as scoped and points full suites to background',
      () {
        final service = McpToolService();
        final runTests =
            service.getOpenAiToolDefinitions().firstWhere(
                  (tool) =>
                      (tool['function']! as Map<String, dynamic>)['name'] ==
                      'run_tests',
                )['function']!
                as Map<String, dynamic>;
        final description = runTests['description'] as String;

        expect(description, contains('specific test file or directory'));
        expect(description, contains('full suites'));
        expect(description, contains('process_start'));
        expect(description, contains('background=true'));
      },
    );

    test('executes git init in a non-repository directory', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mcp_tool_service_git_init_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final service = McpToolService();
      final result = await service.executeTool(
        name: 'git_execute_command',
        arguments: {'command': 'init', 'working_directory': tempDir.path},
      );

      final decoded = jsonDecode(result.result) as Map<String, dynamic>;
      expect(result.isSuccess, isTrue);
      expect(decoded['exit_code'], 0);
      expect(Directory('${tempDir.path}/.git').existsSync(), isTrue);
    });

    test('finishes a worktree session from the base worktree', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mcp_tool_service_finish_worktree_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final baseDir = Directory('${tempDir.path}/repo')..createSync();
      final worktreeDir = Directory('${tempDir.path}/repo-worktree');

      await _runGit(['init', '-b', 'main'], workingDirectory: baseDir.path);
      await _runGit([
        'config',
        'user.email',
        'test@example.com',
      ], workingDirectory: baseDir.path);
      await _runGit([
        'config',
        'user.name',
        'Test User',
      ], workingDirectory: baseDir.path);
      await File('${baseDir.path}/README.md').writeAsString('base\n');
      await _runGit(['add', 'README.md'], workingDirectory: baseDir.path);
      await _runGit([
        'commit',
        '-m',
        'Initial commit',
      ], workingDirectory: baseDir.path);
      await _runGit([
        'worktree',
        'add',
        '-b',
        'feature/worktree-finish',
        worktreeDir.path,
      ], workingDirectory: baseDir.path);
      await File('${worktreeDir.path}/feature.txt').writeAsString('done\n');
      await _runGit(['add', 'feature.txt'], workingDirectory: worktreeDir.path);
      await _runGit([
        'commit',
        '-m',
        'Add feature file',
      ], workingDirectory: worktreeDir.path);
      await _runGit([
        'worktree',
        'lock',
        '--reason',
        'test lock',
        worktreeDir.path,
      ], workingDirectory: baseDir.path);

      final service = McpToolService();
      final result = await service.executeTool(
        name: 'git_finish_worktree_session',
        arguments: {
          'worktree_path': worktreeDir.path,
          'base_branch': 'main',
          'remove_worktree': true,
        },
      );

      final decoded = jsonDecode(result.result) as Map<String, dynamic>;
      expect(result.isSuccess, isTrue);
      expect(decoded['code'], 'git_finish_worktree_completed');
      expect(decoded['base_worktree_path'], baseDir.resolveSymbolicLinksSync());
      expect(decoded['current_branch'], 'feature/worktree-finish');
      expect(decoded['removed_worktree'], isTrue);
      expect((decoded['merge'] as Map<String, dynamic>)['exit_code'], 0);
      expect((decoded['unlock'] as Map<String, dynamic>)['exit_code'], 0);
      expect((decoded['remove'] as Map<String, dynamic>)['exit_code'], 0);
      expect(File('${baseDir.path}/feature.txt').readAsStringSync(), 'done\n');
      expect(worktreeDir.existsSync(), isFalse);
    });

    test('returns failure for non-zero git command results', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mcp_tool_service_git_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Process.run('git', ['init'], workingDirectory: tempDir.path);
      await File('${tempDir.path}/README.md').writeAsString('hello\n');

      final service = McpToolService();
      final result = await service.executeTool(
        name: 'git_execute_command',
        arguments: {
          'command': 'add README.md && commit -m "Add README"',
          'working_directory': tempDir.path,
        },
      );

      final decoded = jsonDecode(result.result) as Map<String, dynamic>;
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('one git subcommand'));
      expect(decoded['exit_code'], 2);
    });

    test('preserves ordered Computer Use definitions and placement', () {
      final unavailableNames = McpToolService()
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toSet();
      expect(
        unavailableNames.intersection(_computerUseToolNames.toSet()),
        isEmpty,
      );

      final service = McpToolService(
        serialPortService: _FakeMcpSerialPortService(),
        computerUseService: _RecordingMacosComputerUseService(),
        browserService: _FakeMcpBrowserSessionService(),
      );
      final definitions = service.getOpenAiToolDefinitions();
      final names = definitions.map(_openAiFunctionName).toList();
      final computerDefinitions = definitions
          .where(
            (tool) => _computerUseToolNames.contains(_openAiFunctionName(tool)),
          )
          .toList();

      expect(
        MacosComputerUseToolPolicy.allToolNames,
        _computerUseToolNames.toSet(),
      );
      expect(
        computerDefinitions.map(_openAiFunctionName),
        _computerUseToolNames,
      );
      final computerStart = names.indexOf(_computerUseToolNames.first);
      final computerEnd = names.indexOf(_computerUseToolNames.last);
      expect(computerStart, names.indexOf(_serialToolNames.last) + 1);
      expect(names.indexOf(_browserToolNames.first), computerEnd + 1);
      expect(_definitionRequired(computerDefinitions[0]), isEmpty);
      expect(_definitionRequired(computerDefinitions[2]), ['section']);
      expect(_definitionRequired(computerDefinitions[11]), isEmpty);
      expect(_definitionRequired(computerDefinitions[14]), ['text']);
      expect(_definitionRequired(computerDefinitions[15]), ['key']);
      expect(_definitionRequired(computerDefinitions[16]), ['direction']);

      final schemaDigest = sha256.convert(
        utf8.encode(jsonEncode(computerDefinitions)),
      );
      expect(
        schemaDigest.toString(),
        'fb9b07ab383c7bb19676ef799b0173500eff7012d98d804a1cbaeeda0548d99e',
      );
    });

    test(
      'hides disabled Computer Use definitions but keeps direct routing',
      () async {
        final computerUse = _RecordingMacosComputerUseService();
        final service = McpToolService(
          computerUseService: computerUse,
          disabledBuiltInTools: _computerUseToolNames.toSet(),
        );
        final names = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toSet();
        expect(names.intersection(_computerUseToolNames.toSet()), isEmpty);

        final result = await service.executeTool(
          name: 'computer_get_permissions',
          arguments: const {},
        );

        expect(result.isSuccess, isTrue);
        expect(result.result, '{"ok":true,"tool":"computer_get_permissions"}');
        expect(computerUse.calls.single.name, 'computer_get_permissions');
        expect(computerUse.calls.single.arguments, isEmpty);
      },
    );

    test(
      'uses an injected Computer Use handler independently of the service',
      () async {
        final computerUse = _RecordingMacosComputerUseService();
        final handler = BuiltInComputerUseToolHandler(
          computerUseService: computerUse,
        );
        final service = McpToolService(computerUseToolHandler: handler);

        final result = await service.executeTool(
          name: 'computer_list_windows',
          arguments: const {'space_scope': 'all'},
        );

        expect(service.computerUseService, isNull);
        expect(service.computerUseToolHandler, same(handler));
        expect(result.isSuccess, isTrue);
        expect(computerUse.calls.single.name, 'computer_list_windows');
        expect(computerUse.calls.single.arguments, {'space_scope': 'all'});
        expect(
          service.getOpenAiToolDefinitions().map(_openAiFunctionName),
          contains('computer_list_windows'),
        );
      },
    );

    test('preserves every Computer Use service dispatch', () async {
      final computerUse = _RecordingMacosComputerUseService();
      final service = McpToolService(computerUseService: computerUse);
      final results = <McpToolResult>[];

      for (final name in _computerUseToolNames) {
        final arguments = switch (name) {
          'computer_request_permissions' => <String, dynamic>{
            'accessibility': false,
            'screen_capture': false,
            'screenCapture': true,
          },
          'computer_open_system_settings' => <String, dynamic>{},
          _ => <String, dynamic>{'marker': name},
        };
        results.add(
          await service.executeTool(name: name, arguments: arguments),
        );
      }

      expect(results.every((result) => result.isSuccess), isTrue);
      expect(computerUse.calls.map((call) => call.name), _computerUseToolNames);
      expect(computerUse.calls[0].arguments, isEmpty);
      expect(computerUse.calls[1].arguments, {
        'accessibility': false,
        'screen_capture': false,
      });
      expect(computerUse.calls[2].arguments, {'section': 'privacy'});
      for (
        var index = 3;
        index < _computerUseToolNames.length - 1;
        index += 1
      ) {
        expect(computerUse.calls[index].arguments, {
          'marker': _computerUseToolNames[index],
        });
      }
      expect(computerUse.calls.last.arguments, isEmpty);
    });

    test(
      'preserves Computer Use permission defaults and legacy alias',
      () async {
        final computerUse = _RecordingMacosComputerUseService();
        final service = McpToolService(computerUseService: computerUse);

        await service.executeTool(
          name: 'computer_request_permissions',
          arguments: const {},
        );
        await service.executeTool(
          name: 'computer_request_permissions',
          arguments: const {'screenCapture': false},
        );
        await service.executeTool(
          name: 'computer_request_permissions',
          arguments: const {'screen_capture': false, 'screenCapture': true},
        );

        expect(computerUse.calls.map((call) => call.arguments), [
          <String, dynamic>{'accessibility': true, 'screen_capture': true},
          <String, dynamic>{'accessibility': true, 'screen_capture': false},
          <String, dynamic>{'accessibility': true, 'screen_capture': false},
        ]);
      },
    );

    test('preserves Computer Use failures and unknown-prefix routing', () async {
      const failedPayload = '{"ok":false,"error":"desktop failed"}';
      final computerUse = _RecordingMacosComputerUseService(
        results: const {
          'computer_click': failedPayload,
          'computer_screenshot': '{"ok":false}',
        },
        errors: {'computer_drag': StateError('drag failed')},
      );
      final available = McpToolService(computerUseService: computerUse);
      final unavailable = McpToolService();

      final failed = await available.executeTool(
        name: 'computer_click',
        arguments: const {},
      );
      final fallback = await available.executeTool(
        name: 'computer_screenshot',
        arguments: const {},
      );
      final unknown = await available.executeTool(
        name: 'computer_custom_action',
        arguments: const {},
      );
      final unavailableUnknown = await unavailable.executeTool(
        name: 'computer_custom_action',
        arguments: const {},
      );

      expect(failed.result, failedPayload);
      expect(failed.isSuccess, isFalse);
      expect(failed.errorMessage, 'desktop failed');
      expect(fallback.isSuccess, isFalse);
      expect(fallback.errorMessage, 'Computer use tool failed');
      expect(unknown.isSuccess, isFalse);
      expect(jsonDecode(unknown.result), {
        'ok': false,
        'code': 'tool_not_available',
        'error':
            'No matching computer use tool is available: computer_custom_action',
      });
      expect(
        unavailableUnknown.errorMessage,
        'macOS computer use tools are unavailable',
      );
      await expectLater(
        available.executeTool(name: 'computer_drag', arguments: const {}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'drag failed',
          ),
        ),
      );
      await expectLater(
        available.executeTool(
          name: 'computer_request_permissions',
          arguments: const {'accessibility': 1},
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('includes macOS computer-use tool definitions when available', () {
      final service = McpToolService(
        computerUseService: _FakeMacosComputerUseService(),
      );

      final functionNames = service
          .getOpenAiToolDefinitions()
          .map(
            (tool) =>
                (tool['function']! as Map<String, dynamic>)['name']! as String,
          )
          .toList();

      expect(functionNames, contains('computer_get_permissions'));
      expect(functionNames, contains('computer_open_system_settings'));
      expect(functionNames, contains('computer_vision_observe'));
      expect(functionNames, contains('computer_accessibility_snapshot'));
      expect(functionNames, contains('computer_list_displays'));
      expect(functionNames, contains('computer_list_windows'));
      expect(functionNames, contains('computer_focus_window'));
      expect(functionNames, contains('computer_screenshot'));
      expect(functionNames, contains('computer_screenshot_window'));
      expect(functionNames, contains('computer_click'));
      expect(functionNames, contains('computer_type_text'));
      expect(functionNames, contains('computer_switch_space'));
      expect(functionNames, contains('computer_start_system_audio_recording'));
    });

    test('exposes computer-use action target metadata for approvals', () {
      final service = McpToolService(
        computerUseService: _FakeMacosComputerUseService(),
      );
      final tools = service.getOpenAiToolDefinitions();

      Map<String, dynamic> parametersFor(String toolName) {
        final tool = tools.singleWhere(
          (tool) =>
              (tool['function']! as Map<String, dynamic>)['name'] == toolName,
        );
        return (tool['function']! as Map<String, dynamic>)['parameters']!
            as Map<String, dynamic>;
      }

      final clickProperties =
          parametersFor('computer_click')['properties']!
              as Map<String, dynamic>;
      final typeTextProperties =
          parametersFor('computer_type_text')['properties']!
              as Map<String, dynamic>;
      final visionProperties =
          parametersFor('computer_vision_observe')['properties']!
              as Map<String, dynamic>;
      final listWindowsProperties =
          parametersFor('computer_list_windows')['properties']!
              as Map<String, dynamic>;
      final switchSpaceProperties =
          parametersFor('computer_switch_space')['properties']!
              as Map<String, dynamic>;

      expect(clickProperties['target'], isA<Map<String, dynamic>>());
      expect(clickProperties['element_id'], isA<Map<String, dynamic>>());
      expect(clickProperties['required'], isNull);
      expect(typeTextProperties['target'], isA<Map<String, dynamic>>());
      expect(typeTextProperties['element_id'], isA<Map<String, dynamic>>());
      expect(typeTextProperties['window_id'], isA<Map<String, dynamic>>());
      expect(visionProperties['include_accessibility'], isA<Map>());
      expect(visionProperties['include_displays'], isA<Map>());
      expect(visionProperties['max_candidate_elements'], isA<Map>());
      expect(visionProperties['space_scope'], isA<Map>());
      expect(listWindowsProperties['space_scope'], isA<Map>());
      expect(listWindowsProperties['include_hidden'], isA<Map>());
      expect(switchSpaceProperties['direction'], isA<Map>());
      expect(
        switchSpaceProperties['direction'],
        containsPair('enum', ['next', 'previous']),
      );
      final target = clickProperties['target'] as Map<String, dynamic>;
      expect(jsonEncode(target), contains('public_action'));
      expect(jsonEncode(target), contains('elementId'));
      expect(jsonEncode(target), contains('appName'));
      expect(jsonEncode(target), contains('windowTitle'));
      expect(jsonEncode(target), contains('secure_field'));
      expect(jsonEncode(target), contains('payment'));
      expect(jsonEncode(target), contains('destructive'));
      expect(jsonEncode(target), contains('publish'));
    });

    test(
      'executes macOS computer-use tools through the native service',
      () async {
        final computerUseService = _FakeMacosComputerUseService();
        final service = McpToolService(computerUseService: computerUseService);

        final result = await service.executeTool(
          name: 'computer_click',
          arguments: const {'window_id': 42, 'element_id': 'ax-0002'},
        );

        expect(result.isSuccess, isTrue);
        expect(computerUseService.calledMethods, ['click']);
        expect(jsonDecode(result.result), containsPair('ok', true));
        expect(jsonDecode(result.result), containsPair('elementId', 'ax-0002'));
      },
    );

    test('executes macOS Space switching through the native service', () async {
      final computerUseService = _FakeMacosComputerUseService();
      final service = McpToolService(computerUseService: computerUseService);

      final result = await service.executeTool(
        name: 'computer_switch_space',
        arguments: const {'direction': 'previous'},
      );

      expect(result.isSuccess, isTrue);
      expect(computerUseService.calledMethods, ['switchSpace']);
      expect(jsonDecode(result.result), containsPair('direction', 'previous'));
    });

    test(
      'executes macOS computer vision observation through the native service',
      () async {
        final computerUseService = _FakeMacosComputerUseService();
        final service = McpToolService(computerUseService: computerUseService);

        final result = await service.executeTool(
          name: 'computer_vision_observe',
          arguments: const {'target': 'front_window', 'max_width': 640},
        );

        expect(result.isSuccess, isTrue);
        expect(computerUseService.calledMethods, ['visionObserve']);
        final decoded = jsonDecode(result.result) as Map<String, dynamic>;
        expect(decoded, containsPair('schemaName', 'test_vision_observation'));
        expect(decoded, containsPair('imageBase64', 'abc123'));
      },
    );

    test(
      'executes macOS accessibility snapshot through the native service',
      () async {
        final computerUseService = _FakeMacosComputerUseService();
        final service = McpToolService(computerUseService: computerUseService);

        final result = await service.executeTool(
          name: 'computer_accessibility_snapshot',
          arguments: const {'target': 'front_window', 'max_elements': 10},
        );

        expect(result.isSuccess, isTrue);
        expect(computerUseService.calledMethods, ['accessibilitySnapshot']);
        final decoded = jsonDecode(result.result) as Map<String, dynamic>;
        expect(
          decoded,
          containsPair(
            'schemaName',
            'macos_computer_use_accessibility_snapshot',
          ),
        );
        expect(decoded, containsPair('readOnly', true));
        expect(decoded['redaction'], containsPair('valuesOmitted', true));
      },
    );

    test(
      'executes macOS display inventory through the native service',
      () async {
        final computerUseService = _FakeMacosComputerUseService();
        final service = McpToolService(computerUseService: computerUseService);

        final result = await service.executeTool(
          name: 'computer_list_displays',
          arguments: const {},
        );

        expect(result.isSuccess, isTrue);
        expect(computerUseService.calledMethods, ['listDisplays']);
        final decoded = jsonDecode(result.result) as Map<String, dynamic>;
        expect(
          decoded,
          containsPair('schemaName', 'macos_computer_use_display_inventory'),
        );
        expect(decoded, containsPair('count', 2));
      },
    );

    test('opens macOS System Settings through the native service', () async {
      final computerUseService = _FakeMacosComputerUseService();
      final service = McpToolService(computerUseService: computerUseService);

      final result = await service.executeTool(
        name: 'computer_open_system_settings',
        arguments: const {'section': 'screen_recording'},
      );

      expect(result.isSuccess, isTrue);
      expect(computerUseService.calledMethods, ['openSystemSettings']);
      expect(
        jsonDecode(result.result),
        containsPair('section', 'screen_recording'),
      );
    });

    test(
      'executes os_get_system_info through the built-in tool service',
      () async {
        final service = McpToolService(
          osLogProcessRunner: (executable, arguments) async {
            if (Platform.isMacOS && executable == '/usr/bin/sw_vers') {
              return ProcessResult(123, 0, '''
ProductName: macOS
ProductVersion: 14.5
BuildVersion: 23F79
''', '');
            }
            if (arguments.join(' ') == '-r') {
              return ProcessResult(124, 0, '23.5.0\n', '');
            }
            if (arguments.join(' ') == '-m') {
              return ProcessResult(125, 0, 'arm64\n', '');
            }
            return ProcessResult(126, 0, '', '');
          },
        );

        final result = await service.executeTool(
          name: 'os_get_system_info',
          arguments: const {},
        );

        expect(result.isSuccess, isTrue);
        final decoded = jsonDecode(result.result) as Map<String, dynamic>;
        expect(decoded['os_family'], isA<String>());
        expect(decoded['os_log_read_supported'], isA<bool>());
      },
    );

    test('executes os_log_read through the built-in tool service', () async {
      final service = McpToolService(
        osLogProcessRunner: (executable, arguments) async =>
            ProcessResult(123, 0, '''
2026-04-22 09:01:00 eapolclient error Authentication failed
2026-04-22 09:02:00 eapolclient notice Auth retry scheduled
''', ''),
      );

      final result = await service.executeTool(
        name: 'os_log_read',
        arguments: const {
          'scope': 'authentication',
          'keywords': ['auth'],
          'max_entries': 1,
        },
      );

      expect(result.isSuccess, isTrue);
      final decoded = jsonDecode(result.result) as Map<String, dynamic>;
      expect(decoded['scope'], 'authentication');
      expect(decoded['entries_returned'], 1);
      final entries = decoded['entries'] as List<dynamic>;
      expect(entries.single, isA<Map<String, dynamic>>());
      expect(
        (entries.single as Map<String, dynamic>)['line'],
        contains('Auth retry scheduled'),
      );
    });

    test(
      'reports connecting state before remote discovery completes',
      () async {
        final toolsCompleter = Completer<List<McpTool>>();
        final client = _FakeMcpClient(
          baseUrl: 'https://pending.example/mcp',
          tools: const [],
          listToolsHandler: () => toolsCompleter.future,
        );
        final service = McpToolService(mcpClients: [client]);

        final connectFuture = service.connect();

        expect(service.status, McpConnectionStatus.connecting);
        expect(service.lastError, isNull);
        expect(service.tools, isEmpty);
        expect(service.serverStates, hasLength(1));
        expect(service.serverStates.single.identifier, client.identifier);
        expect(
          service.serverStates.single.status,
          McpConnectionStatus.connecting,
        );

        toolsCompleter.complete([
          McpTool(
            name: 'remote_pending',
            description: 'Pending remote tool',
            inputSchema: const {'type': 'object'},
          ),
        ]);
        await connectFuture;

        expect(service.status, McpConnectionStatus.connected);
        expect(service.tools.single.name, 'remote_pending');
        expect(
          service.serverStates.single.status,
          McpConnectionStatus.connected,
        );
      },
    );

    test('keeps successful remote tools when another server fails', () async {
      final successfulClient = _FakeMcpClient(
        baseUrl: 'https://healthy.example/mcp',
        tools: [
          McpTool(
            name: 'remote_healthy',
            description: 'Healthy remote tool',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      final failedClient = _FakeMcpClient(
        baseUrl: 'https://failed.example/mcp',
        tools: const [],
        listToolsError: StateError('list failed'),
      );
      final service = McpToolService(
        mcpClients: [successfulClient, failedClient],
      );

      await service.connect();

      expect(service.status, McpConnectionStatus.connected);
      expect(service.tools.map((tool) => tool.name), ['remote_healthy']);
      expect(
        service.lastError,
        '${failedClient.identifier}: Bad state: list failed',
      );
      expect(service.serverStates, hasLength(2));
      expect(service.serverStates.map((state) => state.identifier), [
        successfulClient.identifier,
        failedClient.identifier,
      ]);
      expect(service.serverStates.map((state) => state.status), [
        McpConnectionStatus.connected,
        McpConnectionStatus.error,
      ]);
      expect(service.serverStates.map((state) => state.toolCount), [1, 0]);
      expect(
        () => service.serverStates.add(
          const McpServerConnectionInfo(
            identifier: 'extra',
            status: McpConnectionStatus.connected,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('clears stale remote bindings when every server fails', () async {
      final successfulClient = _FakeMcpClient(
        baseUrl: 'https://initial.example/mcp',
        tools: [
          McpTool(
            name: 'remote_initial',
            description: 'Initial remote tool',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      final clients = <McpClientBase>[successfulClient];
      final service = McpToolService(mcpClients: clients);
      await service.connect();
      final staleToolName = service.tools.single.name;

      clients[0] = _FakeMcpClient(
        baseUrl: 'https://failed.example/mcp',
        tools: const [],
        listToolsError: StateError('offline'),
      );
      await service.connect();

      expect(service.status, McpConnectionStatus.error);
      expect(service.tools, isEmpty);
      expect(
        service.lastError,
        'https://failed.example/mcp: Bad state: offline',
      );
      expect(service.serverStates.single.toolCount, 0);
      expect(service.serverStates.single.status, McpConnectionStatus.error);
      final staleResult = await service.executeTool(
        name: staleToolName,
        arguments: const {},
      );
      expect(staleResult.isSuccess, isFalse);
      expect(
        staleResult.errorMessage,
        'No matching tool available: $staleToolName',
      );
    });

    test('refresh reconnects the configured MCP clients', () async {
      final client = _FakeMcpClient(
        baseUrl: 'https://refresh.example/mcp',
        tools: [
          McpTool(
            name: 'remote_refresh',
            description: 'Refresh remote tool',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      final service = McpToolService(mcpClients: [client]);

      await service.connect();
      await service.refresh();

      expect(client.listToolsCallCount, 2);
      expect(service.status, McpConnectionStatus.connected);
      expect(service.tools.single.name, 'remote_refresh');
    });

    test('refresh preserves the overridable connect contract', () async {
      final service = _RefreshRecordingMcpToolService();

      await service.refresh();

      expect(service.connectCallCount, 1);
    });

    test('empty override URL list wins and clears configured state', () async {
      final client = _FakeMcpClient(
        baseUrl: 'https://configured.example/mcp',
        tools: [
          McpTool(
            name: 'remote_configured',
            description: 'Configured remote tool',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      final service = McpToolService(mcpClients: [client]);
      await service.connect();

      await service.connect(
        overrideUrls: const [],
        overrideUrl: 'https://must-not-connect.example/mcp',
      );

      expect(client.listToolsCallCount, 1);
      expect(service.status, McpConnectionStatus.disconnected);
      expect(service.lastError, isNull);
      expect(service.tools, isEmpty);
      expect(service.serverStates, isEmpty);
    });

    test('blocked server override clears configured remote state', () async {
      final client = _FakeMcpClient(
        baseUrl: 'https://configured.example/mcp',
        tools: [
          McpTool(
            name: 'remote_configured',
            description: 'Configured remote tool',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      final service = McpToolService(mcpClients: [client]);
      await service.connect();

      await service.connect(
        overrideServers: const [
          McpServerConfig(
            url: 'https://blocked.example/mcp',
            trustState: McpServerTrustState.blocked,
          ),
        ],
      );

      expect(client.listToolsCallCount, 1);
      expect(service.status, McpConnectionStatus.disconnected);
      expect(service.lastError, isNull);
      expect(service.tools, isEmpty);
      expect(service.serverStates, isEmpty);
    });

    test('uses SearXNG only when no connected remote tools exist', () async {
      final clients = <McpClientBase>[
        _FakeMcpClient(baseUrl: 'https://empty.example/mcp', tools: const []),
      ];
      final service = McpToolService(
        mcpClients: clients,
        searxngClient: SearxngClient(baseUrl: 'https://search.example'),
      );

      await service.connect();

      expect(service.status, McpConnectionStatus.connected);
      expect(service.tools, isEmpty);
      expect(
        service.getOpenAiToolDefinitions().map(_openAiFunctionName),
        contains('web_search'),
      );

      clients[0] = _FakeMcpClient(
        baseUrl: 'https://tools.example/mcp',
        tools: [
          McpTool(
            name: 'remote_catalog',
            description: 'Remote catalog tool',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      await service.connect();

      final names = service
          .getOpenAiToolDefinitions()
          .map(_openAiFunctionName)
          .toList();
      expect(names, contains('remote_catalog'));
      expect(names, isNot(contains('web_search')));
    });

    test('namespaces duplicate remote tools in client order', () async {
      final firstClient = _FakeMcpClient(
        baseUrl: 'https://duplicate.example/mcp',
        tools: [
          McpTool(
            name: 'remote_duplicate',
            description: 'First duplicate',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      final secondClient = _FakeMcpClient(
        baseUrl: 'https://duplicate.example/mcp',
        tools: [
          McpTool(
            name: 'remote_duplicate',
            description: 'Second duplicate',
            inputSchema: const {'type': 'object'},
          ),
        ],
      );
      final service = McpToolService(mcpClients: [firstClient, secondClient]);

      await service.connect();

      expect(service.tools, hasLength(2));
      expect(service.tools.map((tool) => tool.description), [
        'First duplicate',
        'Second duplicate',
      ]);
      expect(service.tools.map((tool) => tool.originalName), [
        'remote_duplicate',
        'remote_duplicate',
      ]);
      expect(service.tools.map((tool) => tool.sourceUrl), [
        firstClient.identifier,
        secondClient.identifier,
      ]);
      expect(service.tools.first.name, startsWith('remote_duplicate__'));
      expect(service.tools.last.name, endsWith('_2'));
      expect(service.tools.map((tool) => tool.name).toSet(), hasLength(2));
      expect(service.tools.every((tool) => tool.name.length <= 64), isTrue);
    });

    test('wraps remote invocation errors after forwarding arguments', () async {
      final client = _FakeMcpClient(
        baseUrl: 'https://call.example/mcp',
        tools: [
          McpTool(
            name: 'remote_call',
            description: 'Remote call tool',
            inputSchema: const {'type': 'object'},
          ),
        ],
        callToolError: StateError('call failed'),
      );
      final service = McpToolService(mcpClients: [client]);
      await service.connect();

      final result = await service.executeTool(
        name: service.tools.single.name,
        arguments: const {'query': 'value', 'limit': 3},
      );

      expect(service.isExternalMcpToolName(service.tools.single.name), isTrue);
      expect(service.isExternalMcpToolName('missing'), isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.isExternalMcpResult, isTrue);
      expect(result.result, isEmpty);
      expect(result.errorMessage, 'Bad state: call failed');
      expect(client.calledToolNames, ['remote_call']);
      expect(client.calledArguments, [
        {'query': 'value', 'limit': 3},
      ]);
    });

    test(
      'namespaces remote tools that collide with built-in tools and routes calls',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://user:secret@example.com:8080/mcp?token=abc',
          tools: [
            McpTool(
              name: 'ping',
              description: 'Remote ping tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: {'ping': 'remote pong'},
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        expect(service.status, McpConnectionStatus.connected);
        expect(service.tools, hasLength(1));

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'ping');
        expect(remoteTool.name, isNot('ping'));
        expect(remoteTool.name, startsWith('ping__'));

        final toolDefinitions = service.getOpenAiToolDefinitions();
        final functionNames = toolDefinitions
            .map(
              (tool) =>
                  (tool['function']! as Map<String, dynamic>)['name']!
                      as String,
            )
            .toList();

        expect(functionNames.where((name) => name == 'ping'), hasLength(1));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {},
        );

        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote pong');
        expect(client.calledToolNames, ['ping']);
      },
    );

    test(
      'namespaces remote tools intercepted before service fallback dispatch',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://intercepted.example.com/mcp',
          tools: _interceptedRemoteCollisionNames
              .map(
                (name) => McpTool(
                  name: name,
                  description: 'Remote $name tool',
                  inputSchema: const {'type': 'object'},
                ),
              )
              .toList(),
          results: {
            for (final name in _interceptedRemoteCollisionNames)
              name: 'remote:$name',
          },
        );
        final service = McpToolService(
          mcpClients: [client],
          skillRepository: SkillRepository.inMemory(),
        );

        await service.connect();

        expect(
          service.tools,
          hasLength(_interceptedRemoteCollisionNames.length),
        );
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames.toSet(), hasLength(functionNames.length));
        for (final remoteTool in service.tools) {
          expect(
            _interceptedRemoteCollisionNames,
            contains(remoteTool.originalName),
          );
          expect(remoteTool.name, startsWith('${remoteTool.originalName}__'));
          expect(
            functionNames.where((name) => name == remoteTool.originalName),
            hasLength(1),
          );
          expect(functionNames, contains(remoteTool.name));

          final result = await service.executeTool(
            name: remoteTool.name,
            arguments: {'source': remoteTool.originalName},
          );
          expect(result.isSuccess, isTrue);
          expect(result.result, 'remote:${remoteTool.originalName}');
        }
        expect(client.calledToolNames, _interceptedRemoteCollisionNames);
        expect(client.calledArguments, [
          for (final name in _interceptedRemoteCollisionNames) {'source': name},
        ]);
      },
    );

    test(
      'disabled or unavailable intercepted names still reserve collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://disabled-intercepted.example.com/mcp',
          tools: _interceptedRemoteCollisionNames
              .map(
                (name) => McpTool(
                  name: name,
                  description: 'Remote $name tool',
                  inputSchema: const {'type': 'object'},
                ),
              )
              .toList(),
          results: {
            for (final name in _interceptedRemoteCollisionNames)
              name: 'remote:$name',
          },
        );
        final service = McpToolService(
          mcpClients: [client],
          disabledBuiltInTools: const {'spawn_subagent', 'get_subagent_result'},
        );

        await service.connect();

        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        for (final name in _interceptedRemoteCollisionNames) {
          expect(functionNames, isNot(contains(name)));
        }
        for (final remoteTool in service.tools) {
          expect(remoteTool.name, startsWith('${remoteTool.originalName}__'));
          expect(functionNames, contains(remoteTool.name));

          final result = await service.executeTool(
            name: remoteTool.name,
            arguments: {'disabled_source': remoteTool.originalName},
          );
          expect(result.isSuccess, isTrue);
          expect(result.result, 'remote:${remoteTool.originalName}');
        }
        expect(client.calledToolNames, _interceptedRemoteCollisionNames);
      },
    );

    test(
      'routes reserved-prefix remote tools through neutral MCP aliases',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://prefixes.example.com/mcp',
          tools: _prefixCollisionRemoteNames
              .map(
                (name) => McpTool(
                  name: name,
                  description: 'Remote $name tool',
                  inputSchema: const {'type': 'object'},
                ),
              )
              .toList(),
          results: {
            for (final name in _prefixCollisionRemoteNames)
              name: 'remote:$name',
          },
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        expect(
          service.tools.map((tool) => tool.originalName),
          _prefixCollisionRemoteNames,
        );
        final definitions = service.getOpenAiToolDefinitions();
        for (final remoteTool in service.tools) {
          final normalizedAlias = remoteTool.name.toLowerCase();
          expect(remoteTool.name, startsWith('mcp__'));
          expect(normalizedAlias, isNot(startsWith('browser_')));
          expect(normalizedAlias, isNot(startsWith('computer_')));
          expect(remoteTool.name.length, lessThanOrEqualTo(64));

          final definition = definitions.singleWhere(
            (tool) => _openAiFunctionName(tool) == remoteTool.name,
          );
          expect(definition[McpToolEntity.openAiExternalToolKey], isTrue);

          final result = await service.executeTool(
            name: remoteTool.name,
            arguments: {'source': remoteTool.originalName},
          );
          expect(result.isSuccess, isTrue);
          expect(result.result, 'remote:${remoteTool.originalName}');
        }
        expect(client.calledToolNames, _prefixCollisionRemoteNames);
        expect(client.calledArguments, [
          for (final name in _prefixCollisionRemoteNames) {'source': name},
        ]);
      },
    );

    test(
      'disabled network names still reserve remote tool collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://example.com/mcp',
          tools: [
            McpTool(
              name: 'ping',
              description: 'Remote ping tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: const {'ping': 'remote pong'},
        );
        final service = McpToolService(
          mcpClients: [client],
          disabledBuiltInTools: const {'ping'},
        );

        await service.connect();

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'ping');
        expect(remoteTool.name, startsWith('ping__'));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames, isNot(contains('ping')));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {},
        );
        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote pong');
        expect(client.calledToolNames, ['ping']);
      },
    );

    test(
      'unavailable SSH names still reserve remote tool collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://ssh-collision.example.com/mcp',
          tools: [
            McpTool(
              name: 'ssh_execute_command',
              description: 'Remote SSH command tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: const {'ssh_execute_command': 'remote ssh command'},
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'ssh_execute_command');
        expect(remoteTool.name, startsWith('ssh_execute_command__'));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames, isNot(contains('ssh_execute_command')));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {'source': 'remote'},
        );
        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote ssh command');
        expect(client.calledToolNames, ['ssh_execute_command']);
        expect(client.calledArguments, [
          {'source': 'remote'},
        ]);
      },
    );

    test(
      'unavailable BLE names still reserve remote tool collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://ble-collision.example.com/mcp',
          tools: [
            McpTool(
              name: 'ble_start_scan',
              description: 'Remote BLE scan tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: const {'ble_start_scan': 'remote scan'},
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'ble_start_scan');
        expect(remoteTool.name, startsWith('ble_start_scan__'));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames, isNot(contains('ble_start_scan')));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {'source': 'remote'},
        );
        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote scan');
        expect(client.calledToolNames, ['ble_start_scan']);
        expect(client.calledArguments, [
          {'source': 'remote'},
        ]);
      },
    );

    test(
      'unavailable WiFi names still reserve remote tool collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://wifi-collision.example.com/mcp',
          tools: [
            McpTool(
              name: 'wifi_scan',
              description: 'Remote WiFi scan tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: const {'wifi_scan': 'remote wifi scan'},
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'wifi_scan');
        expect(remoteTool.name, startsWith('wifi_scan__'));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames, isNot(contains('wifi_scan')));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {'source': 'remote'},
        );
        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote wifi scan');
        expect(client.calledToolNames, ['wifi_scan']);
        expect(client.calledArguments, [
          {'source': 'remote'},
        ]);
      },
    );

    test(
      'unavailable LAN scan names still reserve remote tool collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://lan-collision.example.com/mcp',
          tools: [
            McpTool(
              name: 'lan_scan',
              description: 'Remote LAN scan tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: const {'lan_scan': 'remote lan scan'},
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'lan_scan');
        expect(remoteTool.name, startsWith('lan_scan__'));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames, isNot(contains('lan_scan')));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {'source': 'remote'},
        );
        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote lan scan');
        expect(client.calledToolNames, ['lan_scan']);
        expect(client.calledArguments, [
          {'source': 'remote'},
        ]);
      },
    );

    test(
      'unavailable serial names still reserve remote tool collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://serial-collision.example.com/mcp',
          tools: [
            McpTool(
              name: 'serial_read',
              description: 'Remote serial read tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: const {'serial_read': 'remote serial read'},
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'serial_read');
        expect(remoteTool.name, startsWith('serial_read__'));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames, isNot(contains('serial_read')));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {'source': 'remote'},
        );
        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote serial read');
        expect(client.calledToolNames, ['serial_read']);
        expect(client.calledArguments, [
          {'source': 'remote'},
        ]);
      },
    );

    test(
      'disabled delete_file still reserves its remote tool collision',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://example.com/mcp',
          tools: [
            McpTool(
              name: 'delete_file',
              description: 'Remote delete tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: const {'delete_file': 'remote delete result'},
        );
        final service = McpToolService(
          mcpClients: [client],
          disabledBuiltInTools: const {'delete_file'},
        );

        await service.connect();

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'delete_file');
        expect(remoteTool.name, startsWith('delete_file__'));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        expect(functionNames, isNot(contains('delete_file')));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {},
        );
        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote delete result');
        expect(client.calledToolNames, ['delete_file']);
      },
    );

    test(
      'disabled filesystem names still reserve all remote collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://filesystem.example.com/mcp',
          tools: _filesystemToolNames
              .map(
                (name) => McpTool(
                  name: name,
                  description: 'Remote $name tool',
                  inputSchema: const {'type': 'object'},
                ),
              )
              .toList(),
          results: {
            for (final name in _filesystemToolNames) name: 'remote:$name',
          },
        );
        final service = McpToolService(
          mcpClients: [client],
          disabledBuiltInTools: _filesystemToolNames.toSet(),
        );

        await service.connect();

        expect(service.tools, hasLength(_filesystemToolNames.length));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        for (final remoteTool in service.tools) {
          expect(_filesystemToolNames, contains(remoteTool.originalName));
          expect(remoteTool.name, startsWith('${remoteTool.originalName}__'));
          expect(functionNames, isNot(contains(remoteTool.originalName)));
          expect(functionNames, contains(remoteTool.name));

          final result = await service.executeTool(
            name: remoteTool.name,
            arguments: const {},
          );
          expect(result.isSuccess, isTrue);
          expect(result.result, 'remote:${remoteTool.originalName}');
        }
        expect(client.calledToolNames, _filesystemToolNames);
      },
    );

    test(
      'disabled local command names still reserve all remote collisions',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://commands.example.com/mcp',
          tools: _localCommandToolNames
              .map(
                (name) => McpTool(
                  name: name,
                  description: 'Remote $name tool',
                  inputSchema: const {'type': 'object'},
                ),
              )
              .toList(),
          results: {
            for (final name in _localCommandToolNames) name: 'remote:$name',
          },
        );
        final service = McpToolService(
          mcpClients: [client],
          disabledBuiltInTools: _localCommandToolNames.toSet(),
        );

        await service.connect();

        expect(service.tools, hasLength(_localCommandToolNames.length));
        final functionNames = service
            .getOpenAiToolDefinitions()
            .map(_openAiFunctionName)
            .toList();
        for (final remoteTool in service.tools) {
          expect(_localCommandToolNames, contains(remoteTool.originalName));
          expect(remoteTool.name, startsWith('${remoteTool.originalName}__'));
          expect(functionNames, isNot(contains(remoteTool.originalName)));
          expect(functionNames, contains(remoteTool.name));

          final result = await service.executeTool(
            name: remoteTool.name,
            arguments: const {},
          );
          expect(result.isSuccess, isTrue);
          expect(result.result, 'remote:${remoteTool.originalName}');
        }
        expect(client.calledToolNames, _localCommandToolNames);
      },
    );

    group('rollback_last_file_change', () {
      late Directory tempDir;
      late McpToolService service;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'mcp_tool_service_test_',
        );
        service = McpToolService();
      });

      tearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('restores the previous file contents', () async {
        final path =
            '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}sample.txt';
        final file = File(path);
        file.createSync(recursive: true);
        file.writeAsStringSync('before\n');

        final writeResult = await service.executeTool(
          name: 'write_file',
          arguments: {'path': path, 'content': 'after\n'},
        );
        expect(writeResult.isSuccess, isTrue);

        final preview = await service.previewLastFileRollbackChange();
        expect(preview, isNotNull);
        expect(preview!.path, path);
        expect(preview.preview, contains('-after'));
        expect(preview.preview, contains('+before'));

        final rollbackResult = await service.executeTool(
          name: 'rollback_last_file_change',
          arguments: const {},
        );
        expect(rollbackResult.isSuccess, isTrue);
        expect(await file.readAsString(), 'before\n');
      });

      test('removes a newly created file', () async {
        final path =
            '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}created.txt';

        final writeResult = await service.executeTool(
          name: 'write_file',
          arguments: {'path': path, 'content': 'created\n'},
        );
        expect(writeResult.isSuccess, isTrue);
        expect(File(path).existsSync(), isTrue);

        final rollbackResult = await service.executeTool(
          name: 'rollback_last_file_change',
          arguments: const {},
        );
        expect(rollbackResult.isSuccess, isTrue);
        expect(File(path).existsSync(), isFalse);
      });

      test('restores a file deleted by delete_file', () async {
        final path =
            '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}obsolete.txt';
        final file = File(path)..createSync(recursive: true);
        file.writeAsStringSync('restore me\n');

        final deleteResult = await service.executeTool(
          name: 'delete_file',
          arguments: {'path': path},
        );
        expect(deleteResult.isSuccess, isTrue);
        expect(file.existsSync(), isFalse);

        final rollbackResult = await service.executeTool(
          name: 'rollback_last_file_change',
          arguments: const {},
        );
        expect(rollbackResult.isSuccess, isTrue);
        expect(await file.readAsString(), 'restore me\n');
      });

      test(
        'rolls back all file changes from the last turn checkpoint',
        () async {
          final separator = Platform.pathSeparator;
          final firstPath =
              '${tempDir.path}${separator}lib${separator}first.txt';
          final secondPath =
              '${tempDir.path}${separator}lib${separator}second.txt';
          final firstFile = File(firstPath)..createSync(recursive: true);
          firstFile.writeAsStringSync('before\n');

          service.beginFileTurnCheckpoint('turn-1');
          final firstWriteResult = await service.executeTool(
            name: 'write_file',
            arguments: {'path': firstPath, 'content': 'after first\n'},
          );
          final secondWriteResult = await service.executeTool(
            name: 'write_file',
            arguments: {'path': secondPath, 'content': 'created\n'},
          );
          final firstEditResult = await service.executeTool(
            name: 'edit_file',
            arguments: {
              'path': firstPath,
              'old_text': 'after first\n',
              'new_text': 'after second\n',
            },
          );
          service.endFileTurnCheckpoint();

          expect(firstWriteResult.isSuccess, isTrue);
          expect(secondWriteResult.isSuccess, isTrue);
          expect(firstEditResult.isSuccess, isTrue);
          expect(await firstFile.readAsString(), 'after second\n');
          expect(File(secondPath).existsSync(), isTrue);

          final preview = await service.previewLastFileTurnCheckpoint();
          expect(preview, isNotNull);
          expect(preview!.turnId, 'turn-1');
          expect(preview.paths, [firstPath, secondPath]);
          expect(preview.preview, contains(firstPath));
          expect(preview.preview, contains(secondPath));

          final rollbackResult = await service.rollbackLastFileTurnCheckpoint();
          expect(rollbackResult.isSuccess, isTrue);
          expect(await firstFile.readAsString(), 'before\n');
          expect(File(secondPath).existsSync(), isFalse);
        },
      );

      test('discards empty turn checkpoints', () async {
        service.beginFileTurnCheckpoint('empty-turn');
        service.endFileTurnCheckpoint();

        expect(await service.previewLastFileTurnCheckpoint(), isNull);
        final rollbackResult = await service.rollbackLastFileTurnCheckpoint();

        expect(rollbackResult.isSuccess, isFalse);
        expect(
          rollbackResult.errorMessage,
          'No recent turn file checkpoint is available to roll back',
        );
      });
    });
  });
}

final class _FakeMcpBrowserSessionService extends BrowserSessionService {
  _FakeMcpBrowserSessionService({this.results = const {}});

  final Map<String, String> results;
  final List<({String name, Map<String, dynamic> arguments})> calls = [];

  @override
  bool get isAvailable => true;

  String _record(String name, Map<String, dynamic> arguments) {
    calls.add((name: name, arguments: Map<String, dynamic>.from(arguments)));
    return results[name] ?? jsonEncode({'ok': true, 'tool': name});
  }

  @override
  Future<String> openUrl(String url) async {
    return _record('browser_open', {'url': url});
  }

  @override
  Future<String> snapshot({int? maxElements}) async {
    return _record('browser_snapshot', {'max_elements': maxElements});
  }

  @override
  Future<String> getContent({String format = 'text', int? maxChars}) async {
    return _record('browser_get_content', {
      'format': format,
      'max_chars': maxChars,
    });
  }

  @override
  Future<String> screenshot() async {
    return _record('browser_screenshot', {});
  }

  @override
  Future<String> waitFor({String? selector, int? timeoutMs}) async {
    return _record('browser_wait', {
      'selector': selector,
      'timeout_ms': timeoutMs,
    });
  }

  @override
  Future<String> navigateHistory(String direction) async {
    return _record('browser_navigate_history', {'direction': direction});
  }

  @override
  String closePanel() {
    return _record('browser_close', {});
  }

  @override
  Future<String> fillField({
    int? ref,
    String? selector,
    required String value,
  }) async {
    return _record('browser_fill', {
      'ref': ref,
      'selector': selector,
      'value': value,
    });
  }

  @override
  Future<String> clickElement({int? ref, String? selector}) async {
    return _record('browser_click', {'ref': ref, 'selector': selector});
  }

  @override
  Future<String> submitForm({String? selector}) async {
    return _record('browser_submit', {'selector': selector});
  }

  @override
  Future<String> evaluateJs(String script) async {
    return _record('browser_eval', {'script': script});
  }

  @override
  Future<String> saveData({
    required String filename,
    required String data,
    String format = 'json',
    String? destination,
  }) async {
    return _record('browser_save_data', {
      'filename': filename,
      'data': data,
      'format': format,
      'destination': destination,
    });
  }
}

final class _RecordingMacosComputerUseService extends MacosComputerUseService {
  _RecordingMacosComputerUseService({
    this.results = const {},
    this.errors = const {},
  });

  final Map<String, String> results;
  final Map<String, Object> errors;
  final List<({String name, Map<String, dynamic> arguments})> calls = [];

  @override
  bool get isAvailable => true;

  String _record(String name, Map<String, dynamic> arguments) {
    calls.add((name: name, arguments: Map<String, dynamic>.from(arguments)));
    final error = errors[name];
    if (error != null) throw error;
    return results[name] ?? jsonEncode({'ok': true, 'tool': name});
  }

  @override
  Future<String> getPermissions() async {
    return _record('computer_get_permissions', {});
  }

  @override
  Future<String> requestPermissions({
    bool accessibility = true,
    bool screenCapture = true,
  }) async {
    return _record('computer_request_permissions', {
      'accessibility': accessibility,
      'screen_capture': screenCapture,
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    return _record('computer_open_system_settings', {'section': section});
  }

  @override
  Future<String> visionObserve(Map<String, dynamic> arguments) async {
    return _record('computer_vision_observe', arguments);
  }

  @override
  Future<String> accessibilitySnapshot(Map<String, dynamic> arguments) async {
    return _record('computer_accessibility_snapshot', arguments);
  }

  @override
  Future<String> listDisplays(Map<String, dynamic> arguments) async {
    return _record('computer_list_displays', arguments);
  }

  @override
  Future<String> listWindows(Map<String, dynamic> arguments) async {
    return _record('computer_list_windows', arguments);
  }

  @override
  Future<String> focusWindow(Map<String, dynamic> arguments) async {
    return _record('computer_focus_window', arguments);
  }

  @override
  Future<String> screenshot(Map<String, dynamic> arguments) async {
    return _record('computer_screenshot', arguments);
  }

  @override
  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    return _record('computer_screenshot_window', arguments);
  }

  @override
  Future<String> moveMouse(Map<String, dynamic> arguments) async {
    return _record('computer_move_mouse', arguments);
  }

  @override
  Future<String> click(Map<String, dynamic> arguments) async {
    return _record('computer_click', arguments);
  }

  @override
  Future<String> drag(Map<String, dynamic> arguments) async {
    return _record('computer_drag', arguments);
  }

  @override
  Future<String> scroll(Map<String, dynamic> arguments) async {
    return _record('computer_scroll', arguments);
  }

  @override
  Future<String> typeText(Map<String, dynamic> arguments) async {
    return _record('computer_type_text', arguments);
  }

  @override
  Future<String> switchSpace(Map<String, dynamic> arguments) async {
    return _record('computer_switch_space', arguments);
  }

  @override
  Future<String> pressKey(Map<String, dynamic> arguments) async {
    return _record('computer_press_key', arguments);
  }

  @override
  Future<String> startSystemAudioRecording(
    Map<String, dynamic> arguments,
  ) async {
    return _record('computer_start_system_audio_recording', arguments);
  }

  @override
  Future<String> stopSystemAudioRecording() async {
    return _record('computer_stop_system_audio_recording', {});
  }
}

class _FakeMacosComputerUseService extends MacosComputerUseService {
  final List<String> calledMethods = [];

  @override
  bool get isAvailable => true;

  @override
  Future<String> click(Map<String, dynamic> arguments) async {
    calledMethods.add('click');
    return jsonEncode({
      'ok': true,
      'x': arguments['x'],
      'y': arguments['y'],
      'elementId': arguments['element_id'],
      'windowId': arguments['window_id'],
    });
  }

  @override
  Future<String> switchSpace(Map<String, dynamic> arguments) async {
    calledMethods.add('switchSpace');
    return jsonEncode({
      'ok': true,
      'schemaName': 'macos_computer_use_space_switch',
      'direction': arguments['direction'],
      'key': arguments['direction'] == 'previous' ? 'left' : 'right',
      'modifiers': ['control'],
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    calledMethods.add('openSystemSettings');
    return jsonEncode({'ok': true, 'section': section});
  }

  @override
  Future<String> visionObserve(Map<String, dynamic> arguments) async {
    calledMethods.add('visionObserve');
    return jsonEncode({
      'ok': true,
      'schemaName': 'test_vision_observation',
      'target': arguments['target'],
      'maxWidth': arguments['max_width'],
      'imageBase64': 'abc123',
      'imageMimeType': 'image/png',
    });
  }

  @override
  Future<String> accessibilitySnapshot(Map<String, dynamic> arguments) async {
    calledMethods.add('accessibilitySnapshot');
    return jsonEncode({
      'ok': true,
      'schemaName': 'macos_computer_use_accessibility_snapshot',
      'readOnly': true,
      'target': arguments['target'],
      'elementCount': 1,
      'redaction': {'valuesOmitted': true},
      'elements': [
        {
          'elementId': 'ax-0001',
          'role': 'AXWindow',
          'label': 'Example',
          'frame': {'x': 0, 'y': 0, 'width': 100, 'height': 100},
          'enabled': true,
          'focused': true,
        },
      ],
    });
  }

  @override
  Future<String> listDisplays(Map<String, dynamic> arguments) async {
    calledMethods.add('listDisplays');
    return jsonEncode({
      'ok': true,
      'schemaName': 'macos_computer_use_display_inventory',
      'count': 2,
      'displays': [
        {'displayId': 1, 'displayIndex': 0, 'isMain': true},
        {'displayId': 2, 'displayIndex': 1, 'isMain': false},
      ],
    });
  }
}

final class _FakeMcpSshService extends SshService {
  _FakeMcpSshService({
    this.connected = false,
    SshExecutionResult? executionResult,
  }) : executionResult =
           executionResult ??
           SshExecutionResult(stdout: '', stderr: '', exitCode: 0);

  bool connected;
  final SshExecutionResult executionResult;
  final List<String> executedCommands = [];
  int disconnectCalls = 0;

  @override
  bool get isConnected => connected;

  @override
  Future<SshExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    executedCommands.add(command);
    return executionResult;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    connected = false;
  }
}

final class _FakeMcpWifiService extends WifiService {
  _FakeMcpWifiService({this.cachedResult = 'cached result'});

  final String cachedResult;
  final List<String?> scanResultSorts = [];

  @override
  String getScanResults({String? sortBy}) {
    scanResultSorts.add(sortBy);
    return cachedResult;
  }
}

final class _FakeMcpLanScanService extends LanScanService {
  _FakeMcpLanScanService({
    this.scanResult = 'scan result',
    this.cachedResult = 'cached result',
  });

  final String scanResult;
  final String cachedResult;
  final List<Map<String, dynamic>> scanCalls = [];
  final List<String?> scanResultSorts = [];

  @override
  Future<String> startScan({
    String? subnet,
    String? ipVersion,
    int timeoutMs = 1000,
    List<int>? ports,
  }) async {
    scanCalls.add({
      'subnet': subnet,
      'ip_version': ipVersion,
      'timeout_ms': timeoutMs,
      'ports': ports,
    });
    return scanResult;
  }

  @override
  String getScanResults({String? sortBy}) {
    scanResultSorts.add(sortBy);
    return cachedResult;
  }
}

final class _FakeMcpSerialPortService extends SerialPortService {
  _FakeMcpSerialPortService({
    this.listResult = 'list result',
    this.readResult = 'read result',
    this.decodeResult = 'decode result',
    this.writeResult = 'write result',
    this.closeResult = 'close result',
  });

  final String listResult;
  final String readResult;
  final String decodeResult;
  final String writeResult;
  final String closeResult;
  int listCalls = 0;
  final List<Map<String, dynamic>> readCalls = [];
  final List<Map<String, dynamic>> decodeCalls = [];
  final List<Map<String, dynamic>> writeCalls = [];
  final List<String> closeCalls = [];

  @override
  String listPorts() {
    listCalls += 1;
    return listResult;
  }

  @override
  String read(
    String portName, {
    String encoding = 'utf8',
    int? maxBytes,
    bool clear = true,
    String? frameDelimiterHex,
    int? frameLength,
    int maxFrames = 200,
    bool includeStats = false,
  }) {
    readCalls.add({
      'port': portName,
      'encoding': encoding,
      'max_bytes': maxBytes,
      'clear': clear,
      'frame_delimiter_hex': frameDelimiterHex,
      'frame_length': frameLength,
      'max_frames': maxFrames,
      'include_stats': includeStats,
    });
    return readResult;
  }

  @override
  String decode({
    String? dataHex,
    String? port,
    required String format,
    List<String>? fields,
    bool consume = false,
  }) {
    decodeCalls.add({
      'data_hex': dataHex,
      'port': port,
      'format': format,
      'fields': fields,
      'consume': consume,
    });
    return decodeResult;
  }

  @override
  Future<String> write(
    String portName,
    String data, {
    String encoding = 'utf8',
  }) async {
    writeCalls.add({'port': portName, 'data': data, 'encoding': encoding});
    return writeResult;
  }

  @override
  Future<String> close(String portName) async {
    closeCalls.add(portName);
    return closeResult;
  }
}

class _FakeMcpClient extends McpClient {
  _FakeMcpClient({
    required super.baseUrl,
    required this.tools,
    Map<String, String>? results,
    this.listToolsHandler,
    this.listToolsError,
    this.callToolError,
  }) : results = results ?? const {};

  final List<McpTool> tools;
  final Map<String, String> results;
  final Future<List<McpTool>> Function()? listToolsHandler;
  final Object? listToolsError;
  final Object? callToolError;
  final List<String> calledToolNames = [];
  final List<Map<String, dynamic>> calledArguments = [];
  int listToolsCallCount = 0;

  @override
  Future<List<McpTool>> listTools() async {
    listToolsCallCount += 1;
    if (listToolsHandler != null) {
      return listToolsHandler!();
    }
    if (listToolsError != null) {
      throw listToolsError!;
    }
    return tools;
  }

  @override
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    calledToolNames.add(name);
    calledArguments.add(Map<String, dynamic>.from(arguments));
    if (callToolError != null) {
      throw callToolError!;
    }
    return results[name] ?? '';
  }
}

class _RefreshRecordingMcpToolService extends McpToolService {
  int connectCallCount = 0;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {
    connectCallCount += 1;
  }
}

Future<ProcessResult> _runGit(
  List<String> args, {
  required String workingDirectory,
}) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
  );
  expect(
    result.exitCode,
    0,
    reason:
        'git ${args.join(' ')} failed in $workingDirectory\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}',
  );
  return result;
}
