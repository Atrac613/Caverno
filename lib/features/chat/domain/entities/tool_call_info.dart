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
    this.fromEarlierLoop = false,
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

  /// Whether this result is being re-sent from an earlier loop iteration
  /// rather than having just arrived.
  ///
  /// The follow-up request carries a bounded tail of earlier read-only results
  /// (`RecentReadResultCarry`), and merging them into the current batch's
  /// assistant turn told the model that eight tools had just returned at once.
  /// Measured on session 95631b24: reasoning grew with the carried count --
  /// 4,002 characters at three carried, 9,977 at six -- to emit a single tool
  /// call, 8.5x the thinking of the run before the carry existed, and 92% of
  /// that growth was reasoning rather than output. History has to look like
  /// history, so the formatter emits these as their own earlier exchanges.
  final bool fromEarlierLoop;
}
