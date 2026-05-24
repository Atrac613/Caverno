import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/google_chat_delivery_service.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/routines/data/routine_execution_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/domain/services/routine_computer_use_action_allowlist.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  Routine buildRoutine({
    bool toolsEnabled = false,
    String prompt = 'Summarize the latest updates.',
    String workspaceDirectory = '',
    bool allowWorkspaceWrites = false,
    RoutineCompletionAction completionAction = RoutineCompletionAction.none,
  }) {
    final now = DateTime(2026, 4, 21, 10);
    return Routine(
      id: 'routine-1',
      name: 'Morning summary',
      prompt: prompt,
      createdAt: now,
      updatedAt: now,
      toolsEnabled: toolsEnabled,
      workspaceDirectory: workspaceDirectory,
      allowWorkspaceWrites: allowWorkspaceWrites,
      completionAction: completionAction,
    );
  }

  group('RoutineExecutionService', () {
    test('falls back to plain chat when tools are disabled', () async {
      final dataSource = _FakeChatDataSource(
        plainResults: [
          ChatCompletionResult(content: 'Plain answer', finishReason: 'stop'),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [_toolDefinition('web_search', 'Search the web')],
        resultsByToolName: const {},
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final record = await service.execute(buildRoutine());

      expect(record.isSuccessful, isTrue);
      expect(record.output, 'Plain answer');
      expect(record.usedTools, isFalse);
      expect(record.toolCallCount, 0);
      expect(dataSource.toolRequestNames, isEmpty);
      expect(toolService.executedCalls, isEmpty);
    });

    test('uses read-only tools when routine tools are enabled', () async {
      final dataSource = _FakeChatDataSource(
        initialToolAwareResult: ChatCompletionResult(
          content: 'Looking up the latest weather',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-1',
              name: 'web_search',
              arguments: const {'query': 'tokyo weather'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        toolLoopResult: ChatCompletionResult(
          content: 'Collected tool results',
          finishReason: 'stop',
        ),
        plainResults: [
          ChatCompletionResult(
            content: 'Tokyo will be sunny today.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [
          _toolDefinition('web_search', 'Search the web'),
          _toolDefinition('write_file', 'Write a file'),
        ],
        resultsByToolName: {
          'web_search': const McpToolResult(
            toolName: 'web_search',
            result: '{"results":[{"title":"Forecast"}]}',
            isSuccess: true,
          ),
        },
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final record = await service.execute(
        buildRoutine(toolsEnabled: true),
        trigger: RoutineRunTrigger.scheduled,
      );

      expect(record.isSuccessful, isTrue);
      expect(record.output, 'Tokyo will be sunny today.');
      expect(record.usedTools, isTrue);
      expect(record.toolCallCount, 1);
      expect(record.toolNames, ['web_search']);
      expect(record.toolCalls, hasLength(1));
      expect(record.toolCalls.single.name, 'web_search');
      expect(record.toolCalls.single.arguments, contains('tokyo weather'));
      expect(record.toolCalls.single.result, contains('Forecast'));
      expect(dataSource.toolRequestNames, ['web_search']);
      expect(dataSource.createChatCompletionWithToolResultsCallCount, 1);
      expect(toolService.executedCalls, hasLength(1));
      expect(toolService.executedCalls.single.name, 'web_search');
      expect(toolService.executedCalls.single.arguments, {
        'query': 'tokyo weather',
      });
    });

    test('allows Computer Use observation tools during routines', () async {
      final dataSource = _FakeChatDataSource(
        initialToolAwareResult: ChatCompletionResult(
          content: 'Observing the current desktop',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-observe',
              name: 'computer_vision_observe',
              arguments: const {'target': 'front_window'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        toolLoopResult: ChatCompletionResult(
          content: 'Collected desktop observation',
          finishReason: 'stop',
        ),
        plainResults: [
          ChatCompletionResult(
            content: 'Safari is the active window.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [
          _toolDefinition('computer_vision_observe', 'Observe the desktop'),
          _toolDefinition('computer_click', 'Click a desktop target'),
        ],
        resultsByToolName: {
          'computer_vision_observe': const McpToolResult(
            toolName: 'computer_vision_observe',
            result: '{"ok":true,"summary":"Safari is active"}',
            isSuccess: true,
          ),
        },
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final record = await service.execute(buildRoutine(toolsEnabled: true));

      expect(record.isSuccessful, isTrue);
      expect(record.toolNames, ['computer_vision_observe']);
      expect(dataSource.toolRequestNames, ['computer_vision_observe']);
      expect(toolService.executedCalls, hasLength(1));
      expect(toolService.executedCalls.single.name, 'computer_vision_observe');
      expect(toolService.executedCalls.single.arguments, {
        'target': 'front_window',
      });
      final systemPrompt = dataSource.lastToolAwareMessages
          .singleWhere((message) => message.role == MessageRole.system)
          .content;
      expect(
        systemPrompt,
        contains('Computer Use is available only for observation'),
      );
      expect(systemPrompt, contains('cannot perform unattended pointer'));
    });

    test('blocks Computer Use action tools during routines', () async {
      final dataSource = _FakeChatDataSource(
        initialToolAwareResult: ChatCompletionResult(
          content: 'Trying to publish from the desktop',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-click',
              name: 'computer_click',
              arguments: const {
                'x': 120,
                'y': 80,
                'target': {
                  'label': 'Post',
                  'role': 'button',
                  'risk': 'public_action',
                },
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        toolLoopResult: ChatCompletionResult(
          content: 'Collected blocked action result',
          finishReason: 'stop',
        ),
        plainResults: [
          ChatCompletionResult(
            content: 'The desktop action was blocked.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [
          _toolDefinition('computer_vision_observe', 'Observe the desktop'),
          _toolDefinition('computer_click', 'Click a desktop target'),
        ],
        resultsByToolName: const {},
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final record = await service.execute(buildRoutine(toolsEnabled: true));

      expect(record.isSuccessful, isTrue);
      expect(record.toolNames, ['computer_click']);
      expect(dataSource.toolRequestNames, ['computer_vision_observe']);
      expect(toolService.executedCalls, isEmpty);
      expect(dataSource.lastToolResults, hasLength(1));
      expect(dataSource.lastToolResults.single.name, 'computer_click');
      expect(
        dataSource.lastToolResults.single.result,
        contains('routine_computer_use_action_denied'),
      );
      expect(
        dataSource.lastToolResults.single.result,
        contains('public-action tools require interactive user approval'),
      );
    });

    test(
      'runs allowlisted Computer Use actions when boundaries match',
      () async {
        MacosComputerUseAuditLog.instance.clear();
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Publishing the approved morning post',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-click',
                name: 'computer_click',
                arguments: const {
                  'x': 120,
                  'y': 80,
                  'target': {
                    'label': 'Post',
                    'role': 'button',
                    'action': 'publish',
                    'risk': 'public_action',
                    'appName': 'Safari',
                    'windowTitle': 'X',
                  },
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected post click result',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: 'The allowlisted post action completed.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('computer_vision_observe', 'Observe the desktop'),
            _toolDefinition('computer_click', 'Click a desktop target'),
          ],
          resultsByToolName: {
            'computer_click': const McpToolResult(
              toolName: 'computer_click',
              result: '{"ok":true}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults().copyWith(
            routineComputerUseActionAllowlist: const [
              RoutineComputerUseActionAllowlistEntry(
                id: 'x-post-button',
                label: 'X Post button',
                toolName: 'computer_click',
                targetLabelContains: 'Post',
                targetRole: 'button',
                targetAction: 'publish',
                targetRisk: 'public_action',
                appNameContains: 'Safari',
                windowTitleContains: 'X',
              ),
            ],
          ),
        );

        final record = await service.execute(buildRoutine(toolsEnabled: true));

        expect(record.isSuccessful, isTrue);
        expect(record.toolNames, ['computer_click']);
        expect(dataSource.toolRequestNames, [
          'computer_vision_observe',
          'computer_click',
        ]);
        expect(toolService.executedCalls, hasLength(1));
        expect(toolService.executedCalls.single.name, 'computer_click');
        expect(
          MacosComputerUseAuditLog.instance.entries.single.approvalResult,
          'routine_allowlist:x-post-button',
        );
        final systemPrompt = dataSource.lastToolAwareMessages
            .singleWhere((message) => message.role == MessageRole.system)
            .content;
        expect(systemPrompt, contains('Computer Use action auto-execution'));
        expect(systemPrompt, contains('target.risk=public_action'));
      },
    );

    test('allows generated text when text input boundaries match', () async {
      MacosComputerUseAuditLog.instance.clear();
      final dataSource = _FakeChatDataSource(
        initialToolAwareResult: ChatCompletionResult(
          content: 'Typing the generated morning post',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-type',
              name: 'computer_type_text',
              arguments: const {
                'text': 'Good morning. The sky looks clear today.',
                'target': {
                  'label': 'Post text',
                  'role': 'text_field',
                  'action': 'type',
                  'risk': 'input',
                  'appName': 'Safari',
                  'windowTitle': 'X',
                },
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        toolLoopResult: ChatCompletionResult(
          content: 'Collected text input result',
          finishReason: 'stop',
        ),
        plainResults: [
          ChatCompletionResult(
            content: 'The generated text was typed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [
          _toolDefinition('computer_vision_observe', 'Observe the desktop'),
          _toolDefinition('computer_type_text', 'Type text'),
        ],
        resultsByToolName: {
          'computer_type_text': const McpToolResult(
            toolName: 'computer_type_text',
            result: '{"ok":true}',
            isSuccess: true,
          ),
        },
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults().copyWith(
          routineComputerUseActionAllowlist: const [
            RoutineComputerUseActionAllowlistEntry(
              id: 'x-post-text-any',
              label: 'X post generated text',
              toolName: 'computer_type_text',
              targetRole: 'text_field',
              targetAction: 'type',
              targetRisk: 'input',
              appNameContains: 'Safari',
              windowTitleContains: 'X',
            ),
          ],
        ),
      );

      final record = await service.execute(buildRoutine(toolsEnabled: true));

      expect(record.isSuccessful, isTrue);
      expect(record.toolNames, ['computer_type_text']);
      expect(dataSource.toolRequestNames, [
        'computer_vision_observe',
        'computer_type_text',
      ]);
      expect(toolService.executedCalls, hasLength(1));
      expect(toolService.executedCalls.single.name, 'computer_type_text');
      expect(
        toolService.executedCalls.single.arguments['text'],
        'Good morning. The sky looks clear today.',
      );
      expect(
        MacosComputerUseAuditLog.instance.entries.single.approvalResult,
        'routine_allowlist:x-post-text-any',
      );
    });

    test(
      'blocks allowlisted Computer Use tools when boundaries do not match',
      () async {
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Trying the wrong public action',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-click',
                name: 'computer_click',
                arguments: const {
                  'x': 120,
                  'y': 80,
                  'target': {
                    'label': 'Delete',
                    'role': 'button',
                    'action': 'delete',
                    'risk': 'destructive',
                    'appName': 'Safari',
                    'windowTitle': 'X',
                  },
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected blocked action result',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: 'The action was blocked by the allowlist.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('computer_vision_observe', 'Observe the desktop'),
            _toolDefinition('computer_click', 'Click a desktop target'),
          ],
          resultsByToolName: const {},
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults().copyWith(
            routineComputerUseActionAllowlist: const [
              RoutineComputerUseActionAllowlistEntry(
                id: 'x-post-button',
                toolName: 'computer_click',
                targetLabelContains: 'Post',
                targetRisk: 'public_action',
              ),
            ],
          ),
        );

        final record = await service.execute(buildRoutine(toolsEnabled: true));

        expect(record.isSuccessful, isTrue);
        expect(record.toolNames, ['computer_click']);
        expect(toolService.executedCalls, isEmpty);
        expect(dataSource.lastToolResults.single.result, contains('denied'));
        expect(
          dataSource.lastToolResults.single.result,
          contains('routine_computer_use_action_denied'),
        );
      },
    );

    test(
      'opens allowlisted Safari URLs through the routine tool',
      () async {
        MacosComputerUseAuditLog.instance.clear();
        final processCalls = <_ProcessCall>[];
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Opening X in Safari',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-safari',
                name: RoutineComputerUseActionAllowlist
                    .routineOpenSafariUrlToolName,
                arguments: const {
                  'url': 'https://x.com/compose/post',
                  'reason': 'Prepare the approved morning post.',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected Safari open result',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: 'Safari opened the approved X compose page.',
              finishReason: 'stop',
            ),
          ],
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          processRunner: (executable, arguments) async {
            processCalls.add(
              _ProcessCall(executable: executable, arguments: arguments),
            );
            return ProcessResult(7, 0, '', '');
          },
          settings: AppSettings.defaults().copyWith(
            routineComputerUseActionAllowlist: const [
              RoutineComputerUseActionAllowlistEntry(
                id: 'x-compose-url',
                label: 'X compose URL',
                toolName: RoutineComputerUseActionAllowlist
                    .routineOpenSafariUrlToolName,
                urlHost: 'x.com',
                urlStartsWith: 'https://x.com/',
              ),
            ],
          ),
        );

        final record = await service.execute(buildRoutine(toolsEnabled: true));

        expect(record.isSuccessful, isTrue);
        expect(record.toolNames, [
          RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName,
        ]);
        expect(dataSource.toolRequestNames, [
          RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName,
        ]);
        expect(processCalls, hasLength(1));
        expect(processCalls.single.executable, '/usr/bin/open');
        expect(processCalls.single.arguments, [
          '-a',
          'Safari',
          'https://x.com/compose/post',
        ]);
        expect(dataSource.lastToolResults.single.result, contains('"ok":true'));
        expect(
          dataSource.lastToolResults.single.result,
          contains('routine_safari_url_open_result'),
        );
        expect(
          MacosComputerUseAuditLog.instance.entries.single.approvalResult,
          'routine_allowlist:x-compose-url',
        );
        final systemPrompt = dataSource.lastToolAwareMessages
            .singleWhere((message) => message.role == MessageRole.system)
            .content;
        expect(systemPrompt, contains('exact allowlisted URL'));
      },
      skip: Platform.isMacOS ? false : 'Safari URL opening is macOS-only.',
    );

    test(
      'injects fresh approved routine plans into execution prompts',
      () async {
        final baseRoutine = buildRoutine(toolsEnabled: true);
        final plannedRoutine = baseRoutine.copyWith(
          planArtifact: RoutinePlanArtifact(
            approvedMarkdown:
                '# Routine Plan\n- Search for updates before answering.',
            approvedSourceHash: baseRoutine.planSourceHash,
            approvedAt: DateTime(2026, 4, 21, 10, 5),
          ),
        );
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Plan followed.',
            finishReason: 'stop',
          ),
        );
        final toolService = _FakeMcpToolService(
          definitions: [_toolDefinition('web_search', 'Search the web')],
          resultsByToolName: const {},
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(plannedRoutine);

        expect(record.isSuccessful, isTrue);
        expect(record.usedPlan, isTrue);
        expect(record.planSourceHash, plannedRoutine.planSourceHash);
        final systemPrompt = dataSource.lastToolAwareMessages
            .singleWhere((message) => message.role == MessageRole.system)
            .content;
        expect(systemPrompt, contains('Approved routine plan'));
        expect(systemPrompt, contains('Search for updates before answering.'));
      },
    );

    test('generates routine plan drafts without executing tools', () async {
      final dataSource = _FakeChatDataSource(
        plainResults: [
          ChatCompletionResult(
            content:
                '<think>Drafting.</think># Routine Plan\n\n## Objective\nSummarize updates.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [_toolDefinition('web_search', 'Search the web')],
        resultsByToolName: const {},
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final markdown = await service.generatePlanDraft(
        buildRoutine(toolsEnabled: true),
      );

      expect(markdown, startsWith('# Routine Plan'));
      expect(markdown, isNot(contains('<think>')));
      expect(dataSource.toolRequestNames, isEmpty);
      final systemPrompt = dataSource.lastPlainMessages
          .singleWhere((message) => message.role == MessageRole.system)
          .content;
      final userPrompt = dataSource.lastPlainMessages
          .singleWhere((message) => message.role == MessageRole.user)
          .content;
      expect(systemPrompt, contains('Routine plan mode'));
      expect(systemPrompt, contains('Do not call tools'));
      expect(userPrompt, contains('Summarize the latest updates.'));
      expect(userPrompt, contains('web_search'));
    });

    test(
      'fails when the final routine answer is truncated thinking only',
      () async {
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Scanning the LAN',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-scan',
                name: 'lan_scan',
                arguments: const {'ip_version': 'auto'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: '<think>I still need to write the state file.</think>',
            finishReason: 'length',
          ),
          plainResults: [
            ChatCompletionResult(
              content: '<think>I need to compare and save the file.</think>',
              finishReason: 'length',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [_toolDefinition('lan_scan', 'Scan the local network')],
          resultsByToolName: {
            'lan_scan': const McpToolResult(
              toolName: 'lan_scan',
              result: '{"hosts":[{"ip":"192.168.100.1"}]}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(buildRoutine(toolsEnabled: true));

        expect(record.isSuccessful, isFalse);
        expect(record.error, contains('truncated'));
        expect(record.output, isEmpty);
        expect(record.toolNames, ['lan_scan']);
      },
    );

    test(
      'adds routine guidance and keeps external MCP tools available',
      () async {
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Checking external router status',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-router',
                name: 'router_health_snapshot',
                arguments: const {'lookback_minutes': 15},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected router status',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: 'Router status is stable.',
              finishReason: 'stop',
            ),
          ],
        );
        final routerTool = McpToolEntity(
          name: 'router_health_snapshot',
          description: 'Summarize router health from an external MCP server',
          inputSchema: const {'type': 'object', 'properties': {}},
          sourceUrl: 'http://router-mcp.local:8765',
        ).toOpenAiTool();
        final zeekTool = McpToolEntity(
          name: 'get_dns_health__zeek_server',
          description: 'Summarize recent Zeek dns.log activity',
          inputSchema: const {'type': 'object', 'properties': {}},
          sourceUrl: 'http://zeek-mcp.local:8765',
        ).toOpenAiTool();
        final localToolWithDisallowedName = _toolDefinition(
          'write_file',
          'Write a file',
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition(
              'interface_info',
              'Inspect local network interfaces',
            ),
            routerTool,
            zeekTool,
            localToolWithDisallowedName,
          ],
          resultsByToolName: {
            'router_health_snapshot': const McpToolResult(
              toolName: 'router_health_snapshot',
              result: '{"status":"stable"}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(buildRoutine(toolsEnabled: true));

        expect(record.output, 'Router status is stable.');
        expect(record.toolNames, ['router_health_snapshot']);
        expect(record.toolSourceLabels, {
          'router_health_snapshot': 'router-mcp.local:8765',
        });
        expect(record.toolDisplayNames, [
          'router_health_snapshot (router-mcp.local:8765)',
        ]);
        expect(toolService.executedCalls.single.name, 'router_health_snapshot');
        expect(toolService.executedCalls.single.arguments, {
          'lookback_minutes': 15,
        });
        expect(dataSource.toolRequestNames, [
          'interface_info',
          'router_health_snapshot',
          'get_dns_health__zeek_server',
        ]);
        final systemPrompt = dataSource.lastToolAwareMessages
            .singleWhere((message) => message.role == MessageRole.system)
            .content;
        expect(systemPrompt, contains('Available tools:'));
        expect(systemPrompt, contains('router_health_snapshot'));
        expect(systemPrompt, contains('get_dns_health__zeek_server'));
        expect(systemPrompt, contains('unattended scheduled/manual routine'));
        expect(systemPrompt, contains('Do not ask the user for confirmation'));
        expect(
          systemPrompt,
          contains('Do not answer with only a proposed tool workflow'),
        );
      },
    );

    test(
      'blocks disallowed built-in tools even when the model asks for them',
      () async {
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Trying to mutate a file',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-write',
                name: 'write_file',
                arguments: const {'path': 'notes.txt', 'content': 'unsafe'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('web_search', 'Search the web'),
            _toolDefinition('write_file', 'Write a file'),
          ],
          resultsByToolName: const {},
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(buildRoutine(toolsEnabled: true));

        expect(dataSource.toolRequestNames, ['web_search']);
        expect(toolService.executedCalls, isEmpty);
        expect(record.isSuccessful, isFalse);
        expect(record.error, contains('without any visible output'));
      },
    );

    test(
      'allows write tools only inside the configured routine workspace',
      () async {
        final workspaceDirectory = '/tmp/caverno-routine-workspace';
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Updating saved LAN state',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-write',
                name: 'write_file',
                arguments: const {
                  'path': 'lan/devices.json',
                  'content': '{"ips":["192.168.1.10"]}',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected write result',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: 'Saved the current LAN device list.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('write_file', 'Write a file'),
            _toolDefinition('edit_file', 'Edit a file'),
          ],
          resultsByToolName: {
            'write_file': const McpToolResult(
              toolName: 'write_file',
              result: '{"bytes_written":26}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(
          buildRoutine(
            toolsEnabled: true,
            workspaceDirectory: workspaceDirectory,
            allowWorkspaceWrites: true,
          ),
        );

        expect(record.isSuccessful, isTrue);
        expect(record.toolNames, ['write_file']);
        expect(dataSource.toolRequestNames, ['write_file', 'edit_file']);
        expect(toolService.executedCalls, hasLength(1));
        expect(toolService.executedCalls.single.name, 'write_file');
        expect(
          toolService.executedCalls.single.arguments['path'],
          '/tmp/caverno-routine-workspace/lan/devices.json',
        );
        final systemPrompt = dataSource.lastToolAwareMessages
            .singleWhere((message) => message.role == MessageRole.system)
            .content;
        expect(systemPrompt, contains('Routine workspace directory:'));
        expect(systemPrompt, contains(workspaceDirectory));
        expect(systemPrompt, contains('Workspace write access is enabled'));
      },
    );

    test(
      'executes embedded final tool calls and normalizes routine workspace writes',
      () async {
        const workspaceDirectory = '/tmp/caverno-routine-workspace';
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Scanning the LAN',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-scan',
                name: 'lan_scan',
                arguments: const {'ip_version': 'auto'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected LAN scan results',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: '''
<|tool_call>call:write_file{contents:<|"|>[
  "192.168.100.1",
  "192.168.100.8"
]
<|"|>,path:<|"|>lan_devices.json<|"|>}<tool_call|>''',
              finishReason: 'stop',
            ),
            ChatCompletionResult(
              content: 'Saved the current LAN device list.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('lan_scan', 'Scan the local network'),
            _toolDefinition('write_file', 'Write a file'),
          ],
          resultsByToolName: {
            'lan_scan': const McpToolResult(
              toolName: 'lan_scan',
              result: '{"hosts":[{"ip":"192.168.100.1"}]}',
              isSuccess: true,
            ),
            'write_file': const McpToolResult(
              toolName: 'write_file',
              result: '{"bytes_written":2}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(
          buildRoutine(
            toolsEnabled: true,
            workspaceDirectory: workspaceDirectory,
            allowWorkspaceWrites: true,
          ),
        );

        expect(record.isSuccessful, isTrue);
        expect(record.output, 'Saved the current LAN device list.');
        expect(record.toolNames, ['lan_scan', 'write_file']);
        expect(record.toolCalls, hasLength(2));
        expect(record.toolCalls.first.name, 'lan_scan');
        expect(record.toolCalls.first.result, contains('192.168.100.1'));
        expect(record.toolCalls.last.name, 'write_file');
        expect(record.toolCalls.last.arguments, contains('lan_devices.json'));
        expect(toolService.executedCalls.map((call) => call.name), [
          'lan_scan',
          'write_file',
        ]);
        expect(
          toolService.executedCalls.last.arguments['path'],
          '/tmp/caverno-routine-workspace/lan_devices.json',
        );
        expect(
          toolService.executedCalls.last.arguments['content'],
          '[\n  "192.168.100.1",\n  "192.168.100.8"\n]',
        );
      },
    );

    test(
      'executes structured final tool calls after collecting routine evidence',
      () async {
        const workspaceDirectory = '/tmp/caverno-routine-workspace';
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Scanning the LAN',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-scan',
                name: 'lan_scan',
                arguments: const {'ip_version': 'auto'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected LAN scan results',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: '',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-write',
                  name: 'write_file',
                  arguments: const {
                    'path': 'lan_devices.json',
                    'content': '[\n  "192.168.100.1"\n]',
                  },
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Saved the current LAN device list.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('lan_scan', 'Scan the local network'),
            _toolDefinition('write_file', 'Write a file'),
          ],
          resultsByToolName: {
            'lan_scan': const McpToolResult(
              toolName: 'lan_scan',
              result: '{"hosts":[{"ip":"192.168.100.1"}]}',
              isSuccess: true,
            ),
            'write_file': const McpToolResult(
              toolName: 'write_file',
              result: '{"bytes_written":1}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(
          buildRoutine(
            toolsEnabled: true,
            workspaceDirectory: workspaceDirectory,
            allowWorkspaceWrites: true,
          ),
        );

        expect(record.isSuccessful, isTrue);
        expect(record.output, 'Saved the current LAN device list.');
        expect(record.toolNames, ['lan_scan', 'write_file']);
        expect(toolService.executedCalls.map((call) => call.name), [
          'lan_scan',
          'write_file',
        ]);
        expect(
          toolService.executedCalls.last.arguments['path'],
          '/tmp/caverno-routine-workspace/lan_devices.json',
        );
      },
    );

    test(
      'resolves relative read paths against the routine workspace',
      () async {
        const workspaceDirectory = '/tmp/caverno-routine-workspace';
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Reading previous routine state',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-read',
                name: 'read_file',
                arguments: const {'path': 'lan_devices.json'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResult: ChatCompletionResult(
            content: 'Collected file contents',
            finishReason: 'stop',
          ),
          plainResults: [
            ChatCompletionResult(
              content: 'Compared the previous device list.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [_toolDefinition('read_file', 'Read a file')],
          resultsByToolName: {
            'read_file': const McpToolResult(
              toolName: 'read_file',
              result: '{"content":"[]"}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          mcpToolService: toolService,
          settings: AppSettings.defaults(),
        );

        final record = await service.execute(
          buildRoutine(
            toolsEnabled: true,
            workspaceDirectory: workspaceDirectory,
          ),
        );

        expect(record.isSuccessful, isTrue);
        expect(record.toolNames, ['read_file']);
        expect(
          toolService.executedCalls.single.arguments['path'],
          '/tmp/caverno-routine-workspace/lan_devices.json',
        );
      },
    );

    test('blocks routine writes outside the configured workspace', () async {
      final dataSource = _FakeChatDataSource(
        initialToolAwareResult: ChatCompletionResult(
          content: 'Trying to write outside the workspace',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-write',
              name: 'write_file',
              arguments: const {
                'path': '/tmp/outside-routine-workspace.txt',
                'content': 'unsafe',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        toolLoopResult: ChatCompletionResult(
          content: 'Collected blocked write result',
          finishReason: 'stop',
        ),
        plainResults: [
          ChatCompletionResult(
            content: 'The write was blocked because it was outside workspace.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [_toolDefinition('write_file', 'Write a file')],
        resultsByToolName: const {},
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final record = await service.execute(
        buildRoutine(
          toolsEnabled: true,
          workspaceDirectory: '/tmp/caverno-routine-workspace',
          allowWorkspaceWrites: true,
        ),
      );

      expect(record.isSuccessful, isTrue);
      expect(record.toolNames, ['write_file']);
      expect(toolService.executedCalls, isEmpty);
      expect(dataSource.lastToolResults, hasLength(1));
      expect(
        dataSource.lastToolResults.single.result,
        contains('routine_workspace_write_denied'),
      );
    });

    test('posts to Google Chat through the routine-only tool', () async {
      final deliveryService = _FakeGoogleChatDeliveryService(
        result: GoogleChatDeliveryResult(
          isSuccessful: true,
          message: 'Posted to Google Chat.',
          deliveredAt: DateTime(2026, 4, 21, 10, 0, 2),
        ),
      );
      final dataSource = _FakeChatDataSource(
        initialToolAwareResult: ChatCompletionResult(
          content: 'New LAN device found',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-chat',
              name: RoutineExecutionService.googleChatPostToolName,
              arguments: const {'text': 'New LAN device: 192.168.1.42'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        toolLoopResult: ChatCompletionResult(
          content: 'Collected Google Chat result',
          finishReason: 'stop',
        ),
        plainResults: [
          ChatCompletionResult(
            content: 'Posted the new device alert.',
            finishReason: 'stop',
          ),
        ],
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        googleChatDeliveryService: deliveryService,
        settings: AppSettings.defaults().copyWith(
          googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
        ),
      );

      final record = await service.execute(
        buildRoutine(
          toolsEnabled: true,
          completionAction: RoutineCompletionAction.promptGoogleChat,
        ),
      );

      expect(record.isSuccessful, isTrue);
      expect(record.toolNames, [
        RoutineExecutionService.googleChatPostToolName,
      ]);
      expect(record.toolSourceLabels, {
        RoutineExecutionService.googleChatPostToolName: 'Google Chat',
      });
      expect(record.toolDisplayNames, [
        '${RoutineExecutionService.googleChatPostToolName} (Google Chat)',
      ]);
      expect(dataSource.toolRequestNames, [
        RoutineExecutionService.googleChatPostToolName,
      ]);
      final systemPrompt = dataSource.lastToolAwareMessages
          .singleWhere((message) => message.role == MessageRole.system)
          .content;
      expect(
        systemPrompt,
        contains('call routine_google_chat_post before the final answer'),
      );
      expect(
        systemPrompt,
        contains('include only those matching items in the Google Chat text'),
      );
      expect(systemPrompt, contains('post only the newly discovered IP list'));
      expect(systemPrompt, contains('Do not include total active hosts'));
      expect(
        dataSource.lastToolAwareMessages.last.content,
        contains('the posted text must include only those matching items'),
      );
      expect(
        dataSource.lastToolAwareMessages.last.content,
        contains('routine_google_chat_post.text must contain only'),
      );
      final googleChatTool = dataSource.lastToolDefinitions.singleWhere(
        (tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] ==
            RoutineExecutionService.googleChatPostToolName,
      );
      final googleChatFunction =
          googleChatTool['function'] as Map<String, dynamic>;
      expect(
        googleChatFunction['description'],
        contains('include only those matching items'),
      );
      expect(
        googleChatFunction['description'],
        contains('Do not include total active hosts'),
      );
      final parameters =
          googleChatFunction['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;
      final textProperty = properties['text'] as Map<String, dynamic>;
      expect(textProperty['description'], contains('For scoped notifications'));
      expect(deliveryService.calls, hasLength(1));
      expect(
        deliveryService.calls.single.webhookUrl,
        'https://chat.googleapis.com/v1/spaces/test',
      );
      expect(deliveryService.calls.single.text, 'New LAN device: 192.168.1.42');
    });

    test(
      'keeps final action budget after evidence collection consumes the loop',
      () async {
        final deliveryService = _FakeGoogleChatDeliveryService();
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Scanning the LAN',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-scan-auto',
                name: 'lan_scan',
                arguments: const {'ip_version': 'auto'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResults: [
            ChatCompletionResult(
              content: 'Reading previous state',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-read',
                  name: 'read_file',
                  arguments: const {'path': 'lan_devices.json'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Checking IPv4 devices',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-scan-ipv4',
                  name: 'lan_scan',
                  arguments: const {'ip_version': 'ipv4'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Reading previous state again',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-read-duplicate',
                  name: 'read_file',
                  arguments: const {'path': 'lan_devices.json'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ],
          plainResults: [
            ChatCompletionResult(
              content: 'Saving updated state',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-write',
                  name: 'write_file',
                  arguments: const {
                    'path': 'lan_devices.json',
                    'content': '["192.168.100.42"]',
                  },
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Posting the new device alert',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-chat',
                  name: RoutineExecutionService.googleChatPostToolName,
                  arguments: const {'text': 'New LAN device: 192.168.100.42'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Routine completed.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('lan_scan', 'Scan the local network'),
            _toolDefinition('read_file', 'Read a file'),
            _toolDefinition('write_file', 'Write a file'),
          ],
          resultsByToolName: {
            'lan_scan': const McpToolResult(
              toolName: 'lan_scan',
              result: '{"hosts":[{"ip":"192.168.100.42"}]}',
              isSuccess: true,
            ),
            'read_file': const McpToolResult(
              toolName: 'read_file',
              result: '{"content":"[]"}',
              isSuccess: true,
            ),
            'write_file': const McpToolResult(
              toolName: 'write_file',
              result: '{"bytes_written":18}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          googleChatDeliveryService: deliveryService,
          mcpToolService: toolService,
          settings: AppSettings.defaults().copyWith(
            googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
          ),
        );

        final record = await service.execute(
          buildRoutine(
            toolsEnabled: true,
            workspaceDirectory: '/tmp/caverno-routine-workspace',
            allowWorkspaceWrites: true,
            completionAction: RoutineCompletionAction.promptGoogleChat,
          ),
        );

        expect(record.isSuccessful, isTrue);
        expect(record.output, 'Routine completed.');
        expect(record.toolNames, [
          'lan_scan',
          'read_file',
          'write_file',
          RoutineExecutionService.googleChatPostToolName,
        ]);
        expect(deliveryService.calls, hasLength(1));
        expect(
          deliveryService.calls.single.text,
          'New LAN device: 192.168.100.42',
        );
      },
    );

    test(
      'recovers when the final answer skips a required workspace write',
      () async {
        final deliveryService = _FakeGoogleChatDeliveryService();
        final dataSource = _FakeChatDataSource(
          initialToolAwareResult: ChatCompletionResult(
            content: 'Reading previous LAN state',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-read',
                name: 'read_file',
                arguments: const {'path': 'lan_devices.json'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          toolLoopResults: [
            ChatCompletionResult(
              content: 'Scanning current LAN state',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-scan',
                  name: 'lan_scan',
                  arguments: const {'ip_version': 'auto'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Evidence collected',
              finishReason: 'stop',
            ),
          ],
          plainResults: [
            ChatCompletionResult(
              content: 'Posting the new device alert before saving state',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-chat',
                  name: RoutineExecutionService.googleChatPostToolName,
                  arguments: const {'text': '192.168.100.24'},
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'The notification was posted successfully.',
              finishReason: 'stop',
            ),
            ChatCompletionResult(
              content: 'Saving the required LAN state',
              toolCalls: [
                ToolCallInfo(
                  id: 'tool-write',
                  name: 'write_file',
                  arguments: const {
                    'path': 'lan_devices.json',
                    'contents': ['192.168.100.1', '192.168.100.24'],
                  },
                ),
              ],
              finishReason: 'tool_calls',
            ),
            ChatCompletionResult(
              content: 'Routine completed.',
              finishReason: 'stop',
            ),
          ],
        );
        final toolService = _FakeMcpToolService(
          definitions: [
            _toolDefinition('read_file', 'Read a file'),
            _toolDefinition('lan_scan', 'Scan the local network'),
            _toolDefinition('write_file', 'Write a file'),
          ],
          resultsByToolName: {
            'read_file': const McpToolResult(
              toolName: 'read_file',
              result: '{"content":["192.168.100.1"]}',
              isSuccess: true,
            ),
            'lan_scan': const McpToolResult(
              toolName: 'lan_scan',
              result:
                  '{"hosts":[{"ip":"192.168.100.1"},{"ip":"192.168.100.24"}]}',
              isSuccess: true,
            ),
            'write_file': const McpToolResult(
              toolName: 'write_file',
              result: '{"bytes_written":42}',
              isSuccess: true,
            ),
          },
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          googleChatDeliveryService: deliveryService,
          mcpToolService: toolService,
          settings: AppSettings.defaults().copyWith(
            googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
          ),
        );

        final record = await service.execute(
          buildRoutine(
            toolsEnabled: true,
            prompt:
                'Run a LAN scan and save the detected device IP list to '
                'lan_devices.json in the routine workspace. If there are newly '
                'discovered IPs, post only the newly discovered IP list to '
                'Google Chat. For this canary, when calling write_file, use '
                'the argument name contents instead of content.',
            workspaceDirectory: '/tmp/caverno-routine-workspace',
            allowWorkspaceWrites: true,
            completionAction: RoutineCompletionAction.promptGoogleChat,
          ),
        );

        expect(record.isSuccessful, isTrue);
        expect(record.output, 'Routine completed.');
        expect(record.toolNames, [
          'read_file',
          'lan_scan',
          RoutineExecutionService.googleChatPostToolName,
          'write_file',
        ]);
        expect(toolService.executedCalls.last.name, 'write_file');
        expect(toolService.executedCalls.last.arguments, contains('contents'));
        expect(
          dataSource.toolAwareMessageContents,
          contains(
            contains('Required tool action(s) are still missing: write_file'),
          ),
        );
        expect(
          dataSource.toolAwareMessageContents,
          contains(contains('use `contents` instead of `content`')),
        );
      },
    );

    test(
      'exposes the prompt-controlled Google Chat tool only when selected',
      () async {
        final dataSource = _FakeChatDataSource(
          plainResults: [
            ChatCompletionResult(
              content: 'No tools used',
              finishReason: 'stop',
            ),
          ],
        );
        final service = RoutineExecutionService(
          dataSource: dataSource,
          settings: AppSettings.defaults().copyWith(
            googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
          ),
        );

        await service.execute(buildRoutine(toolsEnabled: true));

        expect(dataSource.toolRequestNames, isEmpty);

        await service.execute(
          buildRoutine(
            toolsEnabled: true,
            completionAction: RoutineCompletionAction.promptGoogleChat,
          ),
        );

        expect(dataSource.toolRequestNames, [
          RoutineExecutionService.googleChatPostToolName,
        ]);
      },
    );
  });
}

Map<String, dynamic> _toolDefinition(String name, String description) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': const {'type': 'object', 'properties': {}},
  },
};

class _FakeChatDataSource implements ChatDataSource {
  _FakeChatDataSource({
    this.initialToolAwareResult,
    this.toolLoopResult,
    List<ChatCompletionResult> toolLoopResults = const [],
    List<ChatCompletionResult> plainResults = const [],
  }) : _toolLoopResults = Queue<ChatCompletionResult>.from(toolLoopResults),
       _plainResults = Queue<ChatCompletionResult>.from(plainResults);

  final ChatCompletionResult? initialToolAwareResult;
  final ChatCompletionResult? toolLoopResult;
  final Queue<ChatCompletionResult> _toolLoopResults;
  final Queue<ChatCompletionResult> _plainResults;
  bool _usedInitialToolAwareResult = false;

  List<String> toolRequestNames = const [];
  List<Message> lastPlainMessages = const [];
  List<Message> lastToolAwareMessages = const [];
  List<Map<String, dynamic>> lastToolDefinitions = const [];
  List<ToolResultInfo> lastToolResults = const [];
  final toolAwareMessageContents = <String>[];
  int createChatCompletionWithToolResultsCallCount = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (tools != null && tools.isNotEmpty) {
      lastToolDefinitions = tools;
      lastToolAwareMessages = messages;
      toolAwareMessageContents.addAll(
        messages.map((message) => message.content),
      );
      toolRequestNames = tools
          .map((tool) => (tool['function'] as Map<String, dynamic>)['name'])
          .whereType<String>()
          .toList(growable: false);
      final initialResult = initialToolAwareResult;
      if (initialResult != null && !_usedInitialToolAwareResult) {
        _usedInitialToolAwareResult = true;
        return initialResult;
      }
      if (_plainResults.isNotEmpty) {
        return _plainResults.removeFirst();
      }
      return ChatCompletionResult(content: '', finishReason: 'stop');
    }

    lastPlainMessages = messages;
    if (_plainResults.isEmpty) {
      return ChatCompletionResult(content: '', finishReason: 'stop');
    }
    return _plainResults.removeFirst();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    createChatCompletionWithToolResultsCallCount += 1;
    lastToolResults = toolResults;
    if (_toolLoopResults.isNotEmpty) {
      return _toolLoopResults.removeFirst();
    }
    return toolLoopResult ??
        ChatCompletionResult(content: '', finishReason: 'stop');
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _FakeMcpToolService extends McpToolService {
  _FakeMcpToolService({
    required this.definitions,
    required this.resultsByToolName,
  });

  final List<Map<String, dynamic>> definitions;
  final Map<String, McpToolResult> resultsByToolName;
  final List<_ExecutedToolCall> executedCalls = [];

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => definitions;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedCalls.add(_ExecutedToolCall(name: name, arguments: arguments));
    return resultsByToolName[name] ??
        McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'Tool result not stubbed',
        );
  }
}

class _ExecutedToolCall {
  const _ExecutedToolCall({required this.name, required this.arguments});

  final String name;
  final Map<String, dynamic> arguments;
}

class _ProcessCall {
  const _ProcessCall({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}

class _FakeGoogleChatDeliveryService extends GoogleChatDeliveryService {
  _FakeGoogleChatDeliveryService({
    this.result = const GoogleChatDeliveryResult(
      isSuccessful: true,
      message: 'Posted to Google Chat.',
    ),
  }) : super();

  final GoogleChatDeliveryResult result;
  final List<_GoogleChatDeliveryCall> calls = [];

  @override
  Future<GoogleChatDeliveryResult> sendMessage({
    required String webhookUrl,
    required String text,
  }) async {
    calls.add(_GoogleChatDeliveryCall(webhookUrl: webhookUrl, text: text));
    return result;
  }
}

class _GoogleChatDeliveryCall {
  const _GoogleChatDeliveryCall({required this.webhookUrl, required this.text});

  final String webhookUrl;
  final String text;
}
