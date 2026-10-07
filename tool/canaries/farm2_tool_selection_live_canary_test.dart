import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/project_farm/application/workspace_control_tools.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// FARM2 live probe: does the model reach the workspace tools on its own?
///
/// The catalogue is the real built-in one, narrowed to the initial
/// `tool_search` selection exactly as production does, so the workspace tools
/// start deferred and the model has to find them. Grading reads only the names
/// of the tools it calls, never its prose.
///
/// ```bash
/// CAVERNO_FARM2_LIVE_CANARY=1 \
/// CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
/// tool/with_live_llm_loopback.sh -- \
///   fvm flutter test tool/canaries/farm2_tool_selection_live_canary_test.dart
/// ```
void main() {
  final enabled = Platform.environment['CAVERNO_FARM2_LIVE_CANARY'] == '1';
  final baseUrl = (Platform.environment['CAVERNO_LLM_BASE_URL'] ?? '')
      .replaceAll(RegExp(r'/+$'), '');
  final model = Platform.environment['CAVERNO_LLM_MODEL'] ?? 'qwen3.8-27b-exl3';

  final t = DateTime.utc(2026, 9, 26);
  final workspace = WorkspaceControlTools(
    projects: () => [
      CodingProject(
        id: 'caverno',
        name: 'caverno',
        rootPath: '/work/caverno',
        createdAt: t,
        updatedAt: t,
      ),
    ],
    conversations: () => [
      Conversation(
        id: 'manager',
        title: 'Manager',
        messages: const [],
        createdAt: t,
        updatedAt: t,
      ),
      Conversation(
        id: 'rc1-soak',
        title: 'RC1 soak',
        messages: const [],
        createdAt: t,
        updatedAt: t,
        workspaceMode: WorkspaceMode.coding,
        projectId: 'caverno',
      ),
    ],
    snapshotFor: (_) => RoadmapSnapshot(
      projectId: 'caverno',
      roadmapPath: 'docs/roadmap.md',
      contentSha256: 'sha',
      extractorVersion: 1,
      model: model,
      extractedAt: t,
      status: RoadmapSnapshotStatus.verified,
      recommended: const RoadmapItemSnapshot(
        id: 'FARM1',
        title: 'Project State and dashboard v1',
        quote: 'Selected 2026-09-26 by user decision',
        line: 97,
      ),
    ),
    isBusy: (_) => false,
    needsApproval: (id) => id == 'rc1-soak',
    callerConversationId: () => 'manager',
  );
  final catalog = McpToolService(
    builtInExtensions: [workspace],
  ).getOpenAiToolDefinitions();

  final cases = <({String prompt, Set<String> expected})>[
    (
      prompt: "What's the next task for my caverno project?",
      expected: {'list_coding_projects', 'get_project_state'},
    ),
    (
      prompt: 'caverno プロジェクトの次のタスクは何？',
      expected: {'list_coding_projects', 'get_project_state'},
    ),
    (
      prompt: 'Which of my coding threads need my approval right now?',
      expected: {'list_coding_projects', 'list_coding_threads'},
    ),
  ];

  for (final probe in cases) {
    test(
      'reaches a workspace tool: ${probe.prompt}',
      () async {
        final called = await _runProbe(
          baseUrl: baseUrl,
          model: model,
          catalog: catalog,
          workspace: workspace,
          prompt: probe.prompt,
        );
        stdout.writeln('[farm2-probe] ${probe.prompt} -> $called');
        expect(
          called.any(probe.expected.contains),
          isTrue,
          reason: 'called $called',
        );
      },
      skip: enabled ? false : 'Set CAVERNO_FARM2_LIVE_CANARY=1',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

Future<List<String>> _runProbe({
  required String baseUrl,
  required String model,
  required List<Map<String, dynamic>> catalog,
  required WorkspaceControlTools workspace,
  required String prompt,
}) async {
  final selected = ToolDefinitionSearchService.buildInitialSelection(catalog);
  final offered = [...selected.toolDefinitions];
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content':
          'You are the assistant inside Caverno, a local coding app. Use tools '
          'when they help answer.',
    },
    {'role': 'user', 'content': prompt},
  ];
  final called = <String>[];
  final client = HttpClient();
  try {
    for (var round = 0; round < 4; round++) {
      final payload = utf8.encode(
        jsonEncode({
          'model': model,
          'temperature': 0,
          'max_tokens': 1500,
          'messages': messages,
          'tools': offered,
        }),
      );
      final request = await client.postUrl(
        Uri.parse('$baseUrl/chat/completions'),
      );
      request.headers.contentType = ContentType.json;
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        fail('HTTP ${response.statusCode}: $body');
      }
      final message =
          ((jsonDecode(body) as Map)['choices'] as List).first['message']
              as Map<String, dynamic>;
      final toolCalls = (message['tool_calls'] as List?) ?? const [];
      if (toolCalls.isEmpty) break;
      messages.add(message);
      for (final raw in toolCalls.cast<Map<String, dynamic>>()) {
        final function = raw['function'] as Map<String, dynamic>;
        final name = function['name'] as String;
        called.add(name);
        final arguments = _arguments(function['arguments']);
        String result;
        if (name == ToolDefinitionSearchService.toolName) {
          result = ToolDefinitionSearchService.searchToolDefinitions(
            definitions: catalog,
            query: '${arguments['query'] ?? ''}',
          );
          // Found tools join the offer, as they do in a production turn.
          for (final match
              in ((jsonDecode(result) as Map)['matched_tools'] as List)
                  .cast<Map>()) {
            final definition = catalog.firstWhere(
              (tool) => (tool['function'] as Map)['name'] == match['name'],
              orElse: () => const {},
            );
            if (definition.isNotEmpty && !offered.contains(definition)) {
              offered.add(definition);
            }
          }
        } else if (WorkspaceControlTools.names.contains(name)) {
          result = (await workspace.execute(name, arguments)).result;
        } else {
          result = 'This tool is unavailable in the probe.';
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': raw['id'],
          'content': result,
        });
      }
      if (called.any(WorkspaceControlTools.names.contains)) break;
    }
  } finally {
    client.close(force: true);
  }
  return called;
}

Map<String, dynamic> _arguments(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  }
  return const {};
}
