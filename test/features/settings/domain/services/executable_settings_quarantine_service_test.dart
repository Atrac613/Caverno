import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/executable_settings_quarantine_service.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ExecutableSettingsQuarantineService();

  test('removes every imported executable authority source', () {
    final trustedAt = DateTime(2026, 8, 14);
    final imported = AppSettings.defaults().copyWith(
      model: 'imported-model',
      mcpEnabled: true,
      mcpUrl: 'https://legacy.example/mcp',
      mcpUrls: const ['https://legacy.example/mcp'],
      mcpServers: [
        McpServerConfig(
          type: McpServerType.stdio,
          command: ' dangerous-command ',
          args: const ['serve'],
          env: const {'TOKEN': 'secret'},
          trustState: McpServerTrustState.trusted,
          trustedAt: trustedAt,
        ),
      ],
      externalToolHooksEnabled: true,
      externalToolHooks: const [
        ExternalToolHook(
          id: ' submit ',
          event: ' UserPromptSubmit ',
          command: ' dangerous-hook ',
          enabled: true,
        ),
      ],
      codingApprovalMode: ToolApprovalMode.fullAccess,
      chatApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      localCommandPermissionRules: const [
        LocalCommandPermissionRule(id: 'rule', pattern: 'dangerous-command'),
      ],
      routineComputerUseActionAllowlist: const [
        RoutineComputerUseActionAllowlistEntry(
          id: 'action',
          toolName: 'computer_click',
          targetLabelContains: 'Allow',
        ),
      ],
    );

    final quarantined = service.quarantineImportedSettings(imported);

    expect(quarantined.model, 'imported-model');
    expect(quarantined.mcpEnabled, isFalse);
    expect(quarantined.mcpUrl, isEmpty);
    expect(quarantined.mcpUrls, isEmpty);
    expect(quarantined.mcpServers, hasLength(1));
    expect(
      quarantined.mcpServers.single.trustState,
      McpServerTrustState.pending,
    );
    expect(quarantined.mcpServers.single.trustedAt, isNull);
    expect(
      quarantined.mcpServers.single.sourceId,
      ExecutableSettingsQuarantineService.importedSettingsSourceId,
    );
    expect(quarantined.enabledMcpServers, isEmpty);
    expect(quarantined.externalToolHooksEnabled, isFalse);
    expect(quarantined.externalToolHooks.single.enabled, isFalse);
    expect(quarantined.externalToolHooks.single.reviewedAt, isNull);
    expect(
      quarantined.externalToolHooks.single.sourceId,
      ExecutableSettingsQuarantineService.importedSettingsSourceId,
    );
    expect(quarantined.externalToolHooks.single.id, 'submit');
    expect(quarantined.externalToolHooks.single.event, 'UserPromptSubmit');
    expect(quarantined.externalToolHooks.single.command, 'dangerous-hook');
    expect(quarantined.codingApprovalMode, ToolApprovalMode.defaultPermissions);
    expect(quarantined.chatApprovalMode, ToolApprovalMode.defaultPermissions);
    expect(quarantined.confirmFileMutations, isTrue);
    expect(quarantined.confirmLocalCommands, isTrue);
    expect(quarantined.confirmGitWrites, isTrue);
    expect(quarantined.localCommandPermissionRules, isEmpty);
    expect(quarantined.routineComputerUseActionAllowlist, isEmpty);
  });

  test('materializes legacy MCP URLs as pending server records', () {
    final imported = AppSettings.defaults().copyWith(
      mcpUrl: 'https://legacy.example/mcp',
      mcpUrls: const ['https://legacy.example/mcp'],
      mcpServers: const [],
    );

    final quarantined = service.quarantineImportedSettings(imported);

    expect(quarantined.mcpServers, hasLength(1));
    expect(
      quarantined.mcpServers.single.trustState,
      McpServerTrustState.pending,
    );
    expect(quarantined.mcpServers.single.url, 'https://legacy.example/mcp');
  });
}
