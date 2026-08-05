import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// Tool call information emitted by the LLM.
class ToolCallInfo {
  ToolCallInfo({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// Tool call result, including the originating arguments for later inspection.
class ToolResultInfo {
  ToolResultInfo({
    required this.id,
    required this.name,
    required this.arguments,
    required this.result,
    this.outcome,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String result;

  /// What the tool reported about its own execution, when it reported
  /// anything.
  ///
  /// `McpToolResult` already carries this, but the tool loop used to build a
  /// `ToolResultInfo` without it, so every downstream consumer that needed an
  /// exit status re-derived one from [result] — three of them still do. The
  /// fact was available at the conversion site and dropped one line later.
  ///
  /// Optional because most producers have nothing structured to report: an
  /// absent outcome means "unknown", never "succeeded". See LL34 in
  /// `docs/local_llm_agent_roadmap.md`.
  final ToolOutcome? outcome;
}
