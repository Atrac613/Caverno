import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_benchmark_app_tool_profile.dart';

void main() {
  group('live benchmark app tool profile', () {
    test('keeps the default headless catalog unchanged', () async {
      final profile = await LiveLlmBenchmarkToolProfile.create(
        mcpServers: const [],
        includeAppToolProfile: false,
      );
      addTearDown(profile.dispose);

      final definitions = profile.service.getOpenAiToolDefinitions();
      final initial = ToolDefinitionSearchService.buildInitialSelection(
        definitions,
      );

      expect(definitions, hasLength(45));
      expect(initial.toolDefinitions, hasLength(22));
    });

    test(
      'reproduces app-service definition groups without executing them',
      () async {
        final profile = await LiveLlmBenchmarkToolProfile.create(
          mcpServers: const [],
          includeAppToolProfile: true,
        );
        addTearDown(profile.dispose);

        final definitions = profile.service.getOpenAiToolDefinitions();
        final names = definitions
            .map(ToolDefinitionSearchService.toolNameFromDefinition)
            .whereType<String>()
            .toSet();
        final initial = ToolDefinitionSearchService.buildInitialSelection(
          definitions,
        );
        final initialNames = initial.toolDefinitions
            .map(ToolDefinitionSearchService.toolNameFromDefinition)
            .whereType<String>()
            .toSet();

        expect(definitions, hasLength(118));
        expect(initial.toolDefinitions, hasLength(38));
        expect(
          names,
          containsAll(<String>{
            'search_past_conversations',
            'recall_memory',
            'load_skill',
            'save_skill',
            'process_start',
            'run_python_script',
            'ssh_connect',
            'ble_start_scan',
            'wifi_scan',
            'lan_scan',
            'serial_list_ports',
            'computer_screenshot',
            'browser_snapshot',
            'web_search',
          }),
        );
        expect(
          initialNames,
          containsAll(<String>{
            'search_past_conversations',
            'recall_memory',
            'load_skill',
            'save_skill',
            'process_start',
            'wifi_scan',
            'lan_scan',
            'web_search',
          }),
        );
        expect(initialNames, isNot(contains('ping6')));
        expect(initialNames, isNot(contains('browser_snapshot')));
        expect(initialNames, isNot(contains('computer_screenshot')));
      },
    );
  });
}
