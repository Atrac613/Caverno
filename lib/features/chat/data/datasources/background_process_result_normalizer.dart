import '../../domain/entities/mcp_tool_entity.dart';
import 'first_party_tool_execution_result.dart';
import 'mcp_tool_result_normalizer.dart';

McpToolResult normalizeProcessResult(
  String name,
  FirstPartyToolExecutionResult execution,
) => McpToolResultNormalizer.success(
  toolName: name,
  result: execution.result,
  outcome: execution.outcome,
);
