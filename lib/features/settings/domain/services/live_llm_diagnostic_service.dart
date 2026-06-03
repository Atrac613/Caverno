import 'dart:convert';

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/services/tool_definition_search_service.dart';
import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';

typedef LiveLlmDiagnosticReportCallback =
    void Function(LiveLlmDiagnosticReport report);

class LiveLlmDiagnosticService {
  LiveLlmDiagnosticService({
    required this.settings,
    required this.chatDataSource,
    required this.mcpToolService,
  });

  final AppSettings settings;
  final ChatDataSource chatDataSource;
  final McpToolService? mcpToolService;

  static const probeDefinitions = <LiveLlmDiagnosticProbeDefinition>[
    LiveLlmDiagnosticProbeDefinition(
      id: _instructionProbeId,
      titleKey: 'settings.live_llm_diag_probe_instruction_title',
      descriptionKey: 'settings.live_llm_diag_probe_instruction_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _narrowToolCallProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_call_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_call_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _toolResultProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_result_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_result_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _initialHarnessProbeId,
      titleKey: 'settings.live_llm_diag_probe_harness_title',
      descriptionKey: 'settings.live_llm_diag_probe_harness_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _toolSearchProbeId,
      titleKey: 'settings.live_llm_diag_probe_tool_search_title',
      descriptionKey: 'settings.live_llm_diag_probe_tool_search_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _subagentProbeId,
      titleKey: 'settings.live_llm_diag_probe_subagent_title',
      descriptionKey: 'settings.live_llm_diag_probe_subagent_desc',
    ),
    LiveLlmDiagnosticProbeDefinition(
      id: _remoteMcpProbeId,
      titleKey: 'settings.live_llm_diag_probe_remote_mcp_title',
      descriptionKey: 'settings.live_llm_diag_probe_remote_mcp_desc',
    ),
  ];

  static const _instructionProbeId = 'instruction_echo';
  static const _narrowToolCallProbeId = 'narrow_tool_call';
  static const _toolResultProbeId = 'tool_result_integration';
  static const _initialHarnessProbeId = 'initial_harness_selection';
  static const _toolSearchProbeId = 'tool_search_catalog';
  static const _subagentProbeId = 'subagent_recognition';
  static const _remoteMcpProbeId = 'remote_mcp_exposure';

  static const _marker = 'CAVERNO_LIVE_DIAGNOSTIC';
  static const _toolResultMarker = 'CAVERNO_TOOL_RESULT_OK';
  static const _subagentMarker = 'CAVERNO_SUBAGENT_DIAGNOSTIC';
  static const _diagnosticTemperature = 0.0;
  static const _diagnosticMaxTokens = 512;

  Future<LiveLlmDiagnosticReport> run({
    LiveLlmDiagnosticReportCallback? onReport,
  }) async {
    final startedAt = DateTime.now();
    var report = LiveLlmDiagnosticReport(
      startedAt: startedAt,
      baseUrl: settings.baseUrl,
      model: settings.model,
      demoMode: settings.demoMode,
      mcpEnabled: settings.mcpEnabled,
      results: [
        for (final definition in probeDefinitions)
          LiveLlmDiagnosticProbeResult(
            id: definition.id,
            status: LiveLlmDiagnosticStatus.pending,
            summary: 'Waiting to run.',
          ),
      ],
    );
    onReport?.call(report);

    final catalogContext = await _loadToolCatalog();
    report = report.copyWith(toolCatalog: catalogContext.catalog);
    onReport?.call(report);

    if (settings.demoMode) {
      report = _skipRemainingAfterLiveRequirement(report);
      report = report.copyWith(finishedAt: DateTime.now());
      onReport?.call(report);
      return report;
    }

    report = await _runProbe(
      report,
      _instructionProbeId,
      onReport,
      _runInstructionProbe,
    );
    report = await _runProbe(
      report,
      _narrowToolCallProbeId,
      onReport,
      () => _runNarrowToolCallProbe(catalogContext),
    );
    report = await _runProbe(
      report,
      _toolResultProbeId,
      onReport,
      () => _runToolResultProbe(catalogContext),
    );
    report = await _runProbe(
      report,
      _initialHarnessProbeId,
      onReport,
      () => _runInitialHarnessProbe(catalogContext),
    );
    report = await _runProbe(
      report,
      _toolSearchProbeId,
      onReport,
      () => _runToolSearchProbe(catalogContext),
    );
    report = await _runProbe(
      report,
      _subagentProbeId,
      onReport,
      () => _runSubagentProbe(catalogContext),
    );
    report = await _runProbe(
      report,
      _remoteMcpProbeId,
      onReport,
      () => _runRemoteMcpProbe(catalogContext),
    );

    report = report.copyWith(finishedAt: DateTime.now());
    onReport?.call(report);
    return report;
  }

  LiveLlmDiagnosticReport _skipRemainingAfterLiveRequirement(
    LiveLlmDiagnosticReport report,
  ) {
    var updated = report.withProbeResult(
      const LiveLlmDiagnosticProbeResult(
        id: _instructionProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'Demo mode is enabled.',
        details: 'Live diagnostics require a real OpenAI-compatible endpoint.',
      ),
    );
    for (final definition in probeDefinitions.skip(1)) {
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: definition.id,
          status: LiveLlmDiagnosticStatus.skipped,
          summary: 'Skipped because demo mode is enabled.',
        ),
      );
    }
    return updated;
  }

  Future<LiveLlmDiagnosticReport> _runProbe(
    LiveLlmDiagnosticReport report,
    String probeId,
    LiveLlmDiagnosticReportCallback? onReport,
    Future<LiveLlmDiagnosticProbeResult> Function() run,
  ) async {
    final startedAt = DateTime.now();
    var updated = report.withProbeResult(
      LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.running,
        summary: 'Running...',
      ),
    );
    onReport?.call(updated);

    try {
      final result = await run();
      updated = updated.withProbeResult(
        result.copyWith(elapsed: DateTime.now().difference(startedAt)),
      );
    } catch (error) {
      updated = updated.withProbeResult(
        LiveLlmDiagnosticProbeResult(
          id: probeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'Probe failed with an exception.',
          details: error.toString(),
          elapsed: DateTime.now().difference(startedAt),
        ),
      );
    }
    onReport?.call(updated);
    return updated;
  }

  Future<_ToolCatalogContext> _loadToolCatalog() async {
    final service = mcpToolService;
    var connectionSummary = '';
    if (!settings.mcpEnabled) {
      return const _ToolCatalogContext(
        definitions: <Map<String, dynamic>>[],
        initialDefinitions: <Map<String, dynamic>>[],
        selectedToolNames: <String>{},
        toolSearchEnabled: false,
        catalog: LiveLlmDiagnosticToolCatalog(
          mcpConnectionSummary: 'MCP tools are disabled in settings.',
        ),
      );
    }
    if (service == null) {
      return const _ToolCatalogContext(
        definitions: <Map<String, dynamic>>[],
        initialDefinitions: <Map<String, dynamic>>[],
        selectedToolNames: <String>{},
        toolSearchEnabled: false,
        catalog: LiveLlmDiagnosticToolCatalog(
          mcpConnectionSummary: 'MCP tool service is unavailable.',
        ),
      );
    }

    try {
      await service.connect();
    } catch (error) {
      connectionSummary = 'Remote MCP connection attempt failed: $error';
    }

    final definitions = service.getOpenAiToolDefinitions();
    final initialSelection = ToolDefinitionSearchService.buildInitialSelection(
      definitions,
    );
    final toolNames = _toolNamesFromDefinitions(definitions);
    final initialToolNames = _toolNamesFromDefinitions(
      initialSelection.toolDefinitions,
    );
    final remoteToolNames = definitions
        .where(_isRemoteMcpTool)
        .map(ToolDefinitionSearchService.toolNameFromDefinition)
        .whereType<String>()
        .toList(growable: false);
    final stateSummary = _mcpStateSummary(service);
    connectionSummary = [
      if (connectionSummary.isNotEmpty) connectionSummary,
      if (stateSummary.isNotEmpty) stateSummary,
    ].join('\n');

    return _ToolCatalogContext(
      definitions: definitions,
      initialDefinitions: initialSelection.toolDefinitions,
      selectedToolNames: initialSelection.selectedToolNames,
      toolSearchEnabled: initialSelection.toolSearchEnabled,
      catalog: LiveLlmDiagnosticToolCatalog(
        totalToolCount: definitions.length,
        initialToolCount: initialSelection.toolDefinitions.length,
        remoteToolCount: remoteToolNames.length,
        remoteServerCount: settings.enabledMcpServers.length,
        toolSearchEnabled: initialSelection.toolSearchEnabled,
        toolNames: toolNames,
        initialToolNames: initialToolNames,
        remoteToolNames: remoteToolNames,
        mcpConnectionSummary: connectionSummary,
      ),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runInstructionProbe() async {
    final result = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'Return exactly this JSON object and no markdown:\n'
            '{"probe":"instruction_echo","status":"ok","marker":"$_marker"}',
      ),
      model: settings.model,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final content = result.content.trim();
    final decoded = _tryDecodeJsonObject(content);
    final jsonPassed =
        decoded?['probe'] == 'instruction_echo' &&
        decoded?['status'] == 'ok' &&
        decoded?['marker'] == _marker;
    final markerPresent = content.contains(_marker);
    if (jsonPassed) {
      return LiveLlmDiagnosticProbeResult(
        id: _instructionProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model followed the exact JSON instruction.',
        modelContent: _preview(content),
        usage: _usage(result),
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _instructionProbeId,
      status: markerPresent
          ? LiveLlmDiagnosticStatus.warning
          : LiveLlmDiagnosticStatus.failed,
      summary: markerPresent
          ? 'The marker was present, but the JSON contract was not exact.'
          : 'The expected diagnostic marker was missing.',
      details: 'Expected marker: $_marker',
      modelContent: _preview(content),
      usage: _usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runNarrowToolCallProbe(
    _ToolCatalogContext catalog,
  ) async {
    final dateTool = _singleTool(catalog.definitions, 'get_current_datetime');
    if (dateTool == null) {
      return _toolProbeUnavailable(_narrowToolCallProbeId);
    }

    final result = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'Call the get_current_datetime tool now. Do not answer in text '
            'before using the tool.',
      ),
      tools: [dateTool],
      model: settings.model,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final toolCalls = result.toolCalls ?? const <ToolCallInfo>[];
    final names = toolCalls.map((call) => call.name).toList(growable: false);
    if (toolCalls.any((call) => call.name == 'get_current_datetime')) {
      return LiveLlmDiagnosticProbeResult(
        id: _narrowToolCallProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model emitted the expected built-in tool call.',
        toolCalls: names,
        modelContent: _preview(result.content),
        usage: _usage(result),
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _narrowToolCallProbeId,
      status: LiveLlmDiagnosticStatus.failed,
      summary: 'The model did not emit get_current_datetime.',
      details: names.isEmpty
          ? 'No tool calls were returned.'
          : names.join(', '),
      modelContent: _preview(result.content),
      toolCalls: names,
      usage: _usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runToolResultProbe(
    _ToolCatalogContext catalog,
  ) async {
    final service = mcpToolService;
    final dateTool = _singleTool(catalog.definitions, 'get_current_datetime');
    if (service == null || dateTool == null) {
      return _toolProbeUnavailable(_toolResultProbeId);
    }

    final messages = _messages(
      user:
          'Call get_current_datetime. After the tool result arrives, return '
          'JSON with probe="datetime_tool_result", marker="$_toolResultMarker", '
          'today copied from relative_dates.today, and timezone copied from the '
          'tool result.',
    );
    final firstResult = await chatDataSource.createChatCompletion(
      messages: messages,
      tools: [dateTool],
      model: settings.model,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final call = (firstResult.toolCalls ?? const <ToolCallInfo>[])
        .where((item) => item.name == 'get_current_datetime')
        .firstOrNull;
    if (call == null) {
      return LiveLlmDiagnosticProbeResult(
        id: _toolResultProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The model did not request the datetime tool.',
        toolCalls: (firstResult.toolCalls ?? const <ToolCallInfo>[])
            .map((item) => item.name)
            .toList(growable: false),
        modelContent: _preview(firstResult.content),
        usage: _usage(firstResult),
      );
    }

    final toolExecution = await service.executeTool(
      name: call.name,
      arguments: call.arguments,
    );
    if (!toolExecution.isSuccess) {
      return LiveLlmDiagnosticProbeResult(
        id: _toolResultProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The built-in datetime tool failed.',
        details: toolExecution.errorMessage ?? toolExecution.result,
        toolCalls: [call.name],
        usage: _usage(firstResult),
      );
    }

    final expected = _tryDecodeJsonObject(toolExecution.result);
    final relativeDates = expected?['relative_dates'];
    final today = relativeDates is Map
        ? relativeDates['today'] as String?
        : null;
    final timezone = expected?['timezone'] as String?;
    final followUp = await chatDataSource.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: call.id.isEmpty ? 'diagnostic-datetime-call' : call.id,
          name: call.name,
          arguments: call.arguments,
          result: toolExecution.result,
        ),
      ],
      tools: [dateTool],
      model: settings.model,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final content = followUp.content.trim();
    final decoded = _tryDecodeJsonObject(content);
    final markerOk =
        decoded?['marker'] == _toolResultMarker ||
        content.contains(_toolResultMarker);
    final todayOk = today == null || content.contains(today);
    final timezoneOk = timezone == null || content.contains(timezone);
    final passed = markerOk && todayOk && timezoneOk;
    return LiveLlmDiagnosticProbeResult(
      id: _toolResultProbeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model integrated the tool result into its final answer.'
          : 'The model answered, but did not clearly copy all tool-result fields.',
      details: [
        if (today != null) 'Expected today: $today',
        if (timezone != null) 'Expected timezone: $timezone',
      ].join('\n'),
      modelContent: _preview(content),
      toolCalls: [call.name],
      usage: _usage(followUp),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runInitialHarnessProbe(
    _ToolCatalogContext catalog,
  ) async {
    if (!catalog.catalog.hasTools) {
      return _toolProbeUnavailable(_initialHarnessProbeId);
    }
    final result = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'Using the currently exposed Caverno initial tool set, call '
            'get_current_datetime exactly once. Do not call tool_search.',
      ),
      tools: catalog.initialDefinitions,
      model: settings.model,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final names = (result.toolCalls ?? const <ToolCallInfo>[])
        .map((call) => call.name)
        .toList(growable: false);
    if (names.contains('get_current_datetime')) {
      return LiveLlmDiagnosticProbeResult(
        id: _initialHarnessProbeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model selected the datetime tool from the harness set.',
        details:
            'Initial tool count: ${catalog.catalog.initialToolCount}. '
            'Tool search enabled: ${catalog.toolSearchEnabled}.',
        toolCalls: names,
        modelContent: _preview(result.content),
        usage: _usage(result),
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _initialHarnessProbeId,
      status: names.contains(ToolDefinitionSearchService.toolName)
          ? LiveLlmDiagnosticStatus.warning
          : LiveLlmDiagnosticStatus.failed,
      summary: names.contains(ToolDefinitionSearchService.toolName)
          ? 'The model used tool_search instead of the directly exposed tool.'
          : 'The model did not select the expected harness tool.',
      details:
          'Initial tool count: ${catalog.catalog.initialToolCount}. '
          'Returned calls: ${names.isEmpty ? "(none)" : names.join(", ")}',
      toolCalls: names,
      modelContent: _preview(result.content),
      usage: _usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runToolSearchProbe(
    _ToolCatalogContext catalog,
  ) async {
    final service = mcpToolService;
    if (!catalog.toolSearchEnabled ||
        !_containsTool(
          catalog.initialDefinitions,
          ToolDefinitionSearchService.toolName,
        )) {
      return const LiveLlmDiagnosticProbeResult(
        id: _toolSearchProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'Tool search is not active for the current tool catalog size.',
      );
    }
    if (service == null) {
      return _toolProbeUnavailable(_toolSearchProbeId);
    }

    final result = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'Use the tool catalog search tool to find a tool for delegating a '
            'focused sub-task to another agent. Call tool_search only.',
      ),
      tools: catalog.initialDefinitions,
      model: settings.model,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final calls = result.toolCalls ?? const <ToolCallInfo>[];
    final names = calls.map((call) => call.name).toList(growable: false);
    final searchCall = calls
        .where((call) => call.name == ToolDefinitionSearchService.toolName)
        .firstOrNull;
    if (searchCall == null) {
      return LiveLlmDiagnosticProbeResult(
        id: _toolSearchProbeId,
        status: names.contains('spawn_subagent')
            ? LiveLlmDiagnosticStatus.warning
            : LiveLlmDiagnosticStatus.failed,
        summary: names.contains('spawn_subagent')
            ? 'The model found subagents directly, but skipped tool_search.'
            : 'The model did not use the tool catalog search tool.',
        toolCalls: names,
        modelContent: _preview(result.content),
        usage: _usage(result),
      );
    }

    final toolResult = await service.executeTool(
      name: searchCall.name,
      arguments: searchCall.arguments,
    );
    final foundSubagent = toolResult.result.contains('spawn_subagent');
    return LiveLlmDiagnosticProbeResult(
      id: _toolSearchProbeId,
      status: foundSubagent
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: foundSubagent
          ? 'The model used tool_search and surfaced the subagent tool.'
          : 'The model used tool_search, but the result did not include subagents.',
      details: _preview(toolResult.result, maxChars: 1200),
      toolCalls: names,
      modelContent: _preview(result.content),
      usage: _usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runSubagentProbe(
    _ToolCatalogContext catalog,
  ) async {
    final subagentTools = _toolsNamed(catalog.definitions, {
      'spawn_subagent',
      'get_subagent_result',
    });
    if (subagentTools.isEmpty) {
      return _toolProbeUnavailable(_subagentProbeId);
    }
    final result = await chatDataSource.createChatCompletion(
      messages: _messages(
        user:
            'For diagnostics only, emit a spawn_subagent tool call with '
            'background=true. The subagent prompt should ask it to summarize '
            'the marker "$_subagentMarker". Do not answer in text.',
      ),
      tools: subagentTools,
      model: settings.model,
      temperature: _diagnosticTemperature,
      maxTokens: _diagnosticMaxTokens,
    );
    final calls = result.toolCalls ?? const <ToolCallInfo>[];
    final names = calls.map((call) => call.name).toList(growable: false);
    final spawnCall = calls
        .where((call) => call.name == 'spawn_subagent')
        .firstOrNull;
    if (spawnCall == null) {
      return LiveLlmDiagnosticProbeResult(
        id: _subagentProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The model did not emit spawn_subagent.',
        toolCalls: names,
        modelContent: _preview(result.content),
        usage: _usage(result),
      );
    }
    final hasPrompt =
        (spawnCall.arguments['prompt'] as String?)?.contains(_subagentMarker) ??
        false;
    final hasDescription =
        (spawnCall.arguments['description'] as String?)?.trim().isNotEmpty ??
        false;
    final background = spawnCall.arguments['background'] == true;
    final passed = hasPrompt && hasDescription && background;
    return LiveLlmDiagnosticProbeResult(
      id: _subagentProbeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model recognized the subagent contract and required fields.'
          : 'The model emitted spawn_subagent, but the arguments were incomplete.',
      details:
          'description=$hasDescription, promptMarker=$hasPrompt, '
          'background=$background',
      toolCalls: names,
      modelContent: _preview(result.content),
      usage: _usage(result),
    );
  }

  Future<LiveLlmDiagnosticProbeResult> _runRemoteMcpProbe(
    _ToolCatalogContext catalog,
  ) async {
    if (catalog.catalog.remoteServerCount == 0) {
      return const LiveLlmDiagnosticProbeResult(
        id: _remoteMcpProbeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'No trusted remote MCP servers are enabled.',
      );
    }
    if (catalog.catalog.remoteToolCount == 0) {
      return LiveLlmDiagnosticProbeResult(
        id: _remoteMcpProbeId,
        status: LiveLlmDiagnosticStatus.warning,
        summary: 'Remote MCP servers are enabled, but no remote tools loaded.',
        details: catalog.catalog.mcpConnectionSummary,
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: _remoteMcpProbeId,
      status: LiveLlmDiagnosticStatus.passed,
      summary:
          'Remote MCP tools are visible to the Caverno harness '
          '(${catalog.catalog.remoteToolCount}).',
      details: [
        catalog.catalog.mcpConnectionSummary,
        'Remote tools: ${catalog.catalog.remoteToolNames.take(12).join(", ")}',
      ].where((line) => line.trim().isNotEmpty).join('\n'),
    );
  }

  LiveLlmDiagnosticProbeResult _toolProbeUnavailable(String probeId) {
    final summary = !settings.mcpEnabled
        ? 'Skipped because MCP tools are disabled in settings.'
        : 'Required diagnostic tools are not available.';
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: !settings.mcpEnabled
          ? LiveLlmDiagnosticStatus.skipped
          : LiveLlmDiagnosticStatus.warning,
      summary: summary,
    );
  }

  List<Message> _messages({required String user}) {
    final now = DateTime.now();
    return [
      Message(
        id: 'live-llm-diagnostic-system-${now.microsecondsSinceEpoch}',
        content:
            'You are running inside Caverno live LLM diagnostics. Follow the '
            'user request exactly. Prefer OpenAI tool calls when the user asks '
            'for a tool.',
        role: MessageRole.system,
        timestamp: now,
      ),
      Message(
        id: 'live-llm-diagnostic-user-${now.microsecondsSinceEpoch}',
        content: user,
        role: MessageRole.user,
        timestamp: now,
      ),
    ];
  }

  List<Map<String, dynamic>> _toolsNamed(
    List<Map<String, dynamic>> definitions,
    Set<String> names,
  ) {
    return definitions
        .where((definition) {
          final name = ToolDefinitionSearchService.toolNameFromDefinition(
            definition,
          );
          return name != null && names.contains(name);
        })
        .toList(growable: false);
  }

  Map<String, dynamic>? _singleTool(
    List<Map<String, dynamic>> definitions,
    String name,
  ) {
    for (final definition in definitions) {
      if (ToolDefinitionSearchService.toolNameFromDefinition(definition) ==
          name) {
        return definition;
      }
    }
    return null;
  }

  bool _containsTool(List<Map<String, dynamic>> definitions, String name) {
    return _singleTool(definitions, name) != null;
  }

  List<String> _toolNamesFromDefinitions(
    Iterable<Map<String, dynamic>> definitions,
  ) {
    return definitions
        .map(ToolDefinitionSearchService.toolNameFromDefinition)
        .whereType<String>()
        .toList(growable: false);
  }

  bool _isRemoteMcpTool(Map<String, dynamic> definition) {
    return definition[McpToolEntity.openAiExternalToolKey] == true;
  }

  String _mcpStateSummary(McpToolService service) {
    if (service.serverStates.isEmpty) {
      if (settings.enabledMcpServers.isEmpty) {
        return 'No trusted remote MCP servers are enabled.';
      }
      return service.lastError ?? '';
    }
    return service.serverStates
        .map((state) {
          final error = state.lastError == null ? '' : ': ${state.lastError}';
          return '${state.identifier}: ${state.status.name}, '
              '${state.toolCount} tool(s)$error';
        })
        .join('\n');
  }

  LiveLlmDiagnosticTokenUsage _usage(ChatCompletionResult result) {
    return LiveLlmDiagnosticTokenUsage(
      promptTokens: result.usage.promptTokens,
      completionTokens: result.usage.completionTokens,
      totalTokens: result.usage.totalTokens,
    );
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String value) {
    final trimmed = value.trim();
    final candidates = <String>[trimmed];
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace > firstBrace) {
      candidates.add(trimmed.substring(firstBrace, lastBrace + 1));
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _preview(String value, {int maxChars = 2000}) {
    final trimmed = value.trim();
    if (trimmed.length <= maxChars) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxChars)}...';
  }
}

class _ToolCatalogContext {
  const _ToolCatalogContext({
    required this.definitions,
    required this.initialDefinitions,
    required this.selectedToolNames,
    required this.toolSearchEnabled,
    required this.catalog,
  });

  final List<Map<String, dynamic>> definitions;
  final List<Map<String, dynamic>> initialDefinitions;
  final Set<String> selectedToolNames;
  final bool toolSearchEnabled;
  final LiveLlmDiagnosticToolCatalog catalog;
}
