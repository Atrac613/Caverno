export 'mcp_tool_service_facade_capabilities.dart';

import 'mcp_tool_service_facade_capabilities.dart';

abstract class McpToolServiceFacadeBase
    with
        McpToolServiceOwnerFacade,
        McpToolServiceFileMutationFacade,
        McpToolServiceFileRollbackFacade,
        McpToolServiceSshFacade {}
