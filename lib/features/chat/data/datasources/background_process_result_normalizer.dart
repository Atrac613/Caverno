import '../../domain/entities/mcp_tool_entity.dart';
import 'command_payload_facts.dart';
import 'mcp_tool_result_normalizer.dart';

McpToolResult normalizeProcessResult(String name, String result) =>
    McpToolResultNormalizer.success(
      toolName: name,
      result: result,
      outcome: CommandPayloadFacts.backgroundProcessOutcome(result),
    );
