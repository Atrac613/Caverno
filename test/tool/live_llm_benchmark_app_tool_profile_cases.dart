part of 'tool_scripts_tiny_test.dart';

/// macOS host-app catalog size from LL39. Computer Use and Browser drop out
/// on platforms where those services are unavailable (Linux CI has neither).
///
/// 117 -> 118: ANA3 PR 2b's accept_task. Reserved and offered like the other
/// two Anabasis tools, so it counts in the host catalog even though only an
/// addressed parent may call it.
const _macosAppProfileDefinitionCount = 118;

/// 37 -> 38: accept_task joined the built-in registry, which is what puts a
/// tool in the initial selection. It was offered in the catalog and absent from
/// this set for five days, so an addressed parent could not call the tool its
/// own prompt told it to use without a tool_search round trip it never made.
///
/// 38 -> 41: the same omission, three more times. inspect_file, delete_file and
/// lsp_go_to_definition were offered in the catalog but never registered, so
/// the F6 guard -- which only walks the registry -- could not see them and the
/// initial selection dropped all three. lsp_go_to_definition had been missing
/// since 2026-06-19: session c79826af shows a coding turn spending ten
/// iterations on search_files variants hunting one symbol, with the tool built
/// for that job absent from its list. The catalog counts are unchanged because
/// these tools were always offered; only the initial selection moves.
const _macosAppProfileInitialCount = 41;

void _runLiveLlmBenchmarkAppToolProfile() {
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

      // 45 -> 46: ANA3 PR 2b's accept_task is reserved and offered like the
      // other two Anabasis tools, so it counts in the headless catalog too.
      // 22 -> 23: and it now loads initially, which the note here originally
      // got backwards. "Not a search-class tool, so it does not displace one"
      // explained why nothing else had to leave; it was read as a reason the
      // initial selection needed no change at all, and the consequence -- the
      // parent being told to record its judgement with a tool absent from its
      // list -- went unnoticed until a live canary showed it never attempted.
      // 23 -> 26: inspect_file, delete_file and lsp_go_to_definition joined the
      // registry for the same reason. The catalog length is unchanged -- all
      // three were already offered; only their classification was missing.
      expect(definitions, hasLength(46));
      expect(initial.toolDefinitions, hasLength(26));
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
            (browserAvailable ? 0 : BuiltInBrowserToolHandler.toolNames.length);

        expect(definitions, hasLength(expectedDefinitionCount));
        expect(
          initial.toolDefinitions,
          hasLength(_macosAppProfileInitialCount),
        );
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
