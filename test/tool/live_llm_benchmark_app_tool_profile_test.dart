import 'dart:io';

import 'package:caverno/core/services/browser_session_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_browser_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/built_in_computer_use_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_benchmark_app_tool_profile.dart';

/// macOS host-app catalog size from LL39. Computer Use and Browser drop out
/// on platforms where those services are unavailable (Linux CI has neither).
const _macosAppProfileDefinitionCount = 117;
const _macosAppProfileInitialCount = 37;

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
        final computerUseAvailable = Platform.isMacOS;
        final browserAvailable = BrowserSessionService.isPlatformSupported;
        final expectedDefinitionCount =
            _macosAppProfileDefinitionCount -
            (computerUseAvailable
                ? 0
                : BuiltInComputerUseToolHandler.toolNames.length) -
            (browserAvailable
                ? 0
                : BuiltInBrowserToolHandler.toolNames.length);

        expect(definitions, hasLength(expectedDefinitionCount));
        expect(initial.toolDefinitions, hasLength(_macosAppProfileInitialCount));
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
          }),
        );
        if (computerUseAvailable) {
          expect(names, contains('computer_screenshot'));
        } else {
          expect(names, isNot(contains('computer_screenshot')));
        }
        if (browserAvailable) {
          expect(names, contains('browser_snapshot'));
        } else {
          expect(names, isNot(contains('browser_snapshot')));
        }
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
          }),
        );
        expect(
          names,
          isNot(contains('web_search')),
          reason: 'search comes from MCP now, not from a Caverno built-in',
        );
        expect(initialNames, isNot(contains('ping6')));
        expect(initialNames, isNot(contains('browser_snapshot')));
        expect(initialNames, isNot(contains('computer_screenshot')));
      },
    );
  });
}
