import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_tool_result_normalizer.dart';

/// Builds the shared fail-closed result for generic ownerless dispatch.
abstract final class OwnerRequiredToolResult {
  static McpToolResult create(String toolName) {
    return McpToolResultNormalizer.structuredFailure(
      toolName: toolName,
      payload: const {
        'ok': false,
        'code': 'chat_turn_owner_required',
        'error': 'An active chat turn owner is required',
      },
      errorMessage: 'An active chat turn owner is required',
    );
  }
}
