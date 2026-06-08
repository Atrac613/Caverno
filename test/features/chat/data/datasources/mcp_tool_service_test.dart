import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_client.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackgroundProcessTools extends BackgroundProcessTools {
  _FakeBackgroundProcessTools({
    required this.statusResults,
    this.startResult = '',
  });

  final Map<String, String> statusResults;
  final String startResult;
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
    test('includes the extended built-in network tool definitions', () {
      final service = McpToolService();

      final functionNames = service
          .getOpenAiToolDefinitions()
          .map(
            (tool) =>
                (tool['function']! as Map<String, dynamic>)['name']! as String,
          )
          .toList();

      expect(functionNames, contains('arp'));
      expect(functionNames, contains('ping6'));
      expect(functionNames, contains('ndp'));
      expect(functionNames, contains('route_lookup'));
      expect(functionNames, contains('interface_info'));
      expect(functionNames, contains('dns_query'));
      expect(functionNames, contains('path_mtu'));
      expect(functionNames, contains('mdns_browse'));
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        expect(functionNames, contains('os_get_system_info'));
        expect(functionNames, contains('run_tests'));
      }
      if (Platform.isMacOS || Platform.isLinux) {
        expect(functionNames, contains('os_log_read'));
      }
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
    });

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
    });
  });
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

class _FakeMcpClient extends McpClient {
  _FakeMcpClient({
    required super.baseUrl,
    required this.tools,
    Map<String, String>? results,
  }) : results = results ?? const {};

  final List<McpTool> tools;
  final Map<String, String> results;
  final List<String> calledToolNames = [];

  @override
  Future<List<McpTool>> listTools() async => tools;

  @override
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    calledToolNames.add(name);
    return results[name] ?? '';
  }
}
