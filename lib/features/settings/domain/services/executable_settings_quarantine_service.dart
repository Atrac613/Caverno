import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/app_settings.dart';

/// Removes executable authority from settings that did not originate from the
/// current local settings editor.
class ExecutableSettingsQuarantineService {
  const ExecutableSettingsQuarantineService();

  static const importedSettingsSourceId = 'import:settings';

  AppSettings quarantineImportedSettings(AppSettings settings) {
    return settings.copyWith(
      mcpEnabled: false,
      mcpUrl: '',
      mcpUrls: const [],
      mcpServers: quarantineMcpServers(settings.effectiveMcpServers),
      externalToolHooksEnabled: false,
      externalToolHooks: quarantineHooks(settings.externalToolHooks),
      codingApprovalMode: ToolApprovalMode.defaultPermissions,
      chatApprovalMode: ToolApprovalMode.defaultPermissions,
      confirmFileMutations: true,
      confirmLocalCommands: true,
      confirmGitWrites: true,
      localCommandPermissionRules: const [],
      routineComputerUseActionAllowlist: const [],
    );
  }

  List<McpServerConfig> quarantineMcpServers(
    Iterable<McpServerConfig> servers,
  ) {
    return [
      for (final server in servers)
        server.copyWith(
          trustState: McpServerTrustState.pending,
          trustedAt: null,
          sourceId: server.sourceId.trim().isEmpty
              ? importedSettingsSourceId
              : server.sourceId.trim(),
        ),
    ];
  }

  List<ExternalToolHook> quarantineHooks(Iterable<ExternalToolHook> hooks) {
    return [
      for (final hook in hooks)
        hook.normalizedForPersistence().copyWith(
          enabled: false,
          reviewedAt: null,
          sourceId: hook.sourceId.trim().isEmpty
              ? importedSettingsSourceId
              : hook.sourceId.trim(),
        ),
    ];
  }
}
