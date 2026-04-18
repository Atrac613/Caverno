import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/settings_notifier.dart';
import '../widgets/mcp_server_approval_sheet.dart';

class McpServersSettingsPage extends ConsumerStatefulWidget {
  const McpServersSettingsPage({super.key});

  @override
  ConsumerState<McpServersSettingsPage> createState() =>
      _McpServersSettingsPageState();
}

class _McpServersSettingsPageState
    extends ConsumerState<McpServersSettingsPage> {
  /// Controllers for the URL field of HTTP servers, keyed by server index.
  final List<TextEditingController> _urlControllers = [];

  /// Controllers for the command field of stdio servers, keyed by server index.
  final List<TextEditingController> _commandControllers = [];

  /// Controllers for the args field of stdio servers, keyed by server index.
  final List<TextEditingController> _argsControllers = [];

  @override
  void initState() {
    super.initState();
    _syncControllers(
      ref.read(settingsNotifierProvider).configuredMcpServers,
    );
  }

  @override
  void dispose() {
    for (final c in _urlControllers) {
      c.dispose();
    }
    for (final c in _commandControllers) {
      c.dispose();
    }
    for (final c in _argsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers(List<McpServerConfig> servers) {
    _syncList(_urlControllers, servers.length);
    _syncList(_commandControllers, servers.length);
    _syncList(_argsControllers, servers.length);

    for (var i = 0; i < servers.length; i++) {
      final server = servers[i];
      _setIfChanged(_urlControllers[i], server.url);
      _setIfChanged(_commandControllers[i], server.command);
      _setIfChanged(_argsControllers[i], server.args.join(' '));
    }
  }

  static void _syncList(List<TextEditingController> list, int target) {
    while (list.length < target) {
      list.add(TextEditingController());
    }
    while (list.length > target) {
      list.removeLast().dispose();
    }
  }

  static void _setIfChanged(TextEditingController controller, String text) {
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  Future<void> _testConnections({
    required AppSettings settings,
    required McpToolService? mcpToolService,
  }) async {
    if (mcpToolService == null) {
      appLog('[Settings] MCP connection test: mcpToolService is null');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('settings.mcp_service_null'.tr())));
      return;
    }

    if (settings.enabledMcpServers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.mcp_no_enabled_servers'.tr())),
      );
      return;
    }

    appLog('[Settings] MCP connection test started');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('settings.mcp_testing'.tr())));

    await mcpToolService.connect();

    if (!mounted) return;

    setState(() {});

    final status = mcpToolService.status;
    final tools = mcpToolService.tools;
    final serverStates = mcpToolService.serverStates;

    appLog(
      '[Settings] MCP connection test result: status=$status, tools=${tools.length}, servers=${serverStates.length}, lastError=${mcpToolService.lastError}',
    );

    if (status == McpConnectionStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'settings.mcp_success'.tr(namedArgs: {'count': '${tools.length}'}),
          ),
        ),
      );
      return;
    }

    final message = status == McpConnectionStatus.disconnected
        ? 'settings.mcp_no_enabled_servers'.tr()
        : 'settings.mcp_failed'.tr(
            namedArgs: {
              'error': mcpToolService.lastError ?? 'common.unknown_error'.tr(),
            },
          );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _reviewServerTrust({
    required int index,
    required McpServerConfig server,
    required SettingsNotifier notifier,
    required McpToolService? mcpToolService,
  }) async {
    if (mcpToolService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.mcp_service_null'.tr())),
      );
      return;
    }

    await mcpToolService.connect(overrideServers: [server]);
    if (!mounted) return;

    final status = mcpToolService.status;
    final toolNames = mcpToolService.tools
        .map((tool) => tool.originalName ?? tool.name)
        .toList(growable: false);
    final trustState = await showModalBottomSheet<McpServerTrustState>(
      context: context,
      isScrollControlled: true,
      builder: (context) => McpServerApprovalSheet(
        server: server,
        toolNames: toolNames,
        connectionError: status == McpConnectionStatus.error
            ? mcpToolService.lastError
            : null,
      ),
    );

    if (trustState != null && trustState != server.trustState) {
      await notifier.updateMcpServerTrustState(index, trustState);
    }
    await mcpToolService.connect();
    if (!mounted) return;
    setState(() {});
  }

  Map<String, McpServerConnectionInfo> _serverStatesById(
    McpToolService? mcpToolService,
  ) {
    if (mcpToolService == null) return const {};
    return {
      for (final state in mcpToolService.serverStates)
        state.identifier: state,
    };
  }

  Widget _buildMcpServerCard({
    required int index,
    required McpServerConfig server,
    required McpServerConnectionInfo? serverState,
    required SettingsNotifier notifier,
    required bool mcpEnabledGlobally,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (statusText, statusIcon, statusColor) = _serverStatusPresentation(
      server: server,
      serverState: serverState,
      mcpEnabledGlobally: mcpEnabledGlobally,
      colorScheme: colorScheme,
    );

    final isStdio = server.type == McpServerType.stdio;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isStdio ? Icons.terminal : Icons.cloud_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isStdio
                        ? 'settings.mcp_cli_server_title'
                            .tr(namedArgs: {'index': '${index + 1}'})
                        : 'settings.mcp_server_title'
                            .tr(namedArgs: {'index': '${index + 1}'}),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: server.enabled,
                  onChanged: (value) =>
                      notifier.updateMcpServerEnabled(index, value),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => notifier.removeMcpServer(index),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'common.delete'.tr(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isStdio) ...[
              TextField(
                controller: _commandControllers[index],
                decoration: InputDecoration(
                  labelText: 'settings.mcp_server_command_label'.tr(),
                  hintText: 'npx',
                  border: const OutlineInputBorder(),
                  helperText: 'settings.mcp_server_command_hint'.tr(),
                ),
                onChanged: (value) =>
                    notifier.updateMcpServerCommand(index, value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _argsControllers[index],
                decoration: InputDecoration(
                  labelText: 'settings.mcp_server_args_label'.tr(),
                  hintText: '-y @modelcontextprotocol/server-filesystem /tmp',
                  border: const OutlineInputBorder(),
                  helperText: 'settings.mcp_server_args_hint'.tr(),
                ),
                onChanged: (value) =>
                    notifier.updateMcpServerArgs(index, value),
              ),
            ] else
              TextField(
                controller: _urlControllers[index],
                decoration: InputDecoration(
                  labelText: 'settings.mcp_server_url_label'.tr(),
                  hintText: 'http://localhost:8081',
                  border: const OutlineInputBorder(),
                  helperText: 'settings.mcp_url_helper'.tr(),
                ),
                keyboardType: TextInputType.url,
                onChanged: (value) =>
                    notifier.updateMcpServerUrl(index, value),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Chip(
                  label: Text(_trustStateLabel(server.trustState)),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                if (server.isValid)
                  TextButton(
                    onPressed: () => _reviewServerTrust(
                      index: index,
                      server: server,
                      notifier: notifier,
                      mcpToolService: ref.read(mcpToolServiceProvider),
                    ),
                    child: Text(
                      server.isTrusted ? 'Review trust' : 'Review & trust',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, IconData, Color) _serverStatusPresentation({
    required McpServerConfig server,
    required McpServerConnectionInfo? serverState,
    required bool mcpEnabledGlobally,
    required ColorScheme colorScheme,
  }) {
    if (!mcpEnabledGlobally) {
      return (
        'settings.mcp_global_disabled'.tr(),
        Icons.toggle_off_outlined,
        Colors.grey,
      );
    }

    if (!server.enabled) {
      return (
        'settings.mcp_server_disabled'.tr(),
        Icons.pause_circle_outline,
        Colors.grey,
      );
    }

    if (server.isBlocked) {
      return ('Server trust is blocked', Icons.block_outlined, colorScheme.error);
    }

    if (server.needsTrustReview) {
      return (
        'Pending trust review',
        Icons.verified_user_outlined,
        colorScheme.primary,
      );
    }

    if (!server.isValid) {
      final hint = server.type == McpServerType.stdio
          ? 'settings.mcp_server_empty_command'.tr()
          : 'settings.mcp_server_empty'.tr();
      return (hint, Icons.edit_outlined, colorScheme.primary);
    }

    if (serverState == null) {
      return ('settings.mcp_disconnected'.tr(), Icons.link_off, Colors.grey);
    }

    return switch (serverState.status) {
      McpConnectionStatus.connected => (
        'settings.mcp_server_tools'.tr(
          namedArgs: {'count': '${serverState.toolCount}'},
        ),
        Icons.check_circle_outline,
        Colors.green,
      ),
      McpConnectionStatus.connecting => (
        'settings.mcp_connecting'.tr(),
        Icons.hourglass_empty,
        colorScheme.primary,
      ),
      McpConnectionStatus.error => (
        'settings.mcp_error'.tr(
          namedArgs: {'error': serverState.lastError ?? 'common.unknown'.tr()},
        ),
        Icons.error_outline,
        colorScheme.error,
      ),
      McpConnectionStatus.disconnected => (
        'settings.mcp_disconnected'.tr(),
        Icons.link_off,
        Colors.grey,
      ),
    };
  }

  String _trustStateLabel(McpServerTrustState trustState) {
    return switch (trustState) {
      McpServerTrustState.pending => 'Pending',
      McpServerTrustState.trusted => 'Trusted',
      McpServerTrustState.blocked => 'Blocked',
    };
  }

  Widget _buildToolsList(McpToolService? mcpToolService) {
    if (mcpToolService == null) {
      return Text(
        'settings.mcp_service_null'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    final status = mcpToolService.status;
    final tools = mcpToolService.tools;

    if (status == McpConnectionStatus.disconnected) {
      return Text(
        'settings.mcp_disconnected'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    if (status == McpConnectionStatus.connecting) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('settings.mcp_connecting'.tr()),
        ],
      );
    }

    if (status == McpConnectionStatus.error) {
      return Text(
        'settings.mcp_error'.tr(
          namedArgs: {
            'error': mcpToolService.lastError ?? 'common.unknown'.tr(),
          },
        ),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    if (tools.isEmpty) {
      return Text(
        'settings.mcp_no_tools'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'settings.mcp_available_tools'.tr(
            namedArgs: {'count': '${tools.length}'},
          ),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        ...tools.map(
          (tool) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text(tool.originalName ?? tool.name),
              subtitle: Text(
                [
                  tool.description,
                  if (tool.sourceUrl != null) tool.sourceUrl!,
                ].join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              dense: true,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final mcpToolService = ref.watch(mcpToolServiceProvider);
    final servers = settings.configuredMcpServers;
    final statesById = _serverStatesById(mcpToolService);

    _syncControllers(servers);

    return Scaffold(
      appBar: AppBar(title: Text('settings.mcp_servers'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Spacer(),
              _AddServerButton(
                onAddHttp: notifier.addMcpServer,
                onAddCli: _isDesktop ? notifier.addMcpStdioServer : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (servers.isEmpty)
            Text(
              'settings.mcp_no_servers'.tr(),
              style: const TextStyle(color: Colors.grey),
            ),
          ...servers.asMap().entries.map((entry) {
            final index = entry.key;
            final server = entry.value;
            final serverState = server.enabled
                ? statesById[server.displayLabel]
                : null;

            return _buildMcpServerCard(
              index: index,
              server: server,
              serverState: serverState,
              notifier: notifier,
              mcpEnabledGlobally: settings.mcpEnabled,
            );
          }),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: settings.mcpEnabled
                ? () => _testConnections(
                    settings: settings,
                    mcpToolService: mcpToolService,
                  )
                : null,
            icon: const Icon(Icons.refresh),
            label: Text('settings.mcp_test_button'.tr()),
          ),
          if (settings.mcpEnabled) ...[
            const SizedBox(height: 12),
            _buildToolsList(mcpToolService),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Add-server button that offers HTTP and (on desktop) CLI options.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({
    required this.onAddHttp,
    this.onAddCli,
  });

  final VoidCallback onAddHttp;
  final VoidCallback? onAddCli;

  @override
  Widget build(BuildContext context) {
    // If CLI is unavailable (non-desktop), show a simple button.
    if (onAddCli == null) {
      return OutlinedButton.icon(
        onPressed: onAddHttp,
        icon: const Icon(Icons.add),
        label: Text('settings.mcp_add_server'.tr()),
      );
    }

    return PopupMenuButton<McpServerType>(
      onSelected: (type) {
        switch (type) {
          case McpServerType.http:
            onAddHttp();
          case McpServerType.stdio:
            onAddCli!();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: McpServerType.http,
          child: ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text('settings.mcp_add_http_server'.tr()),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: McpServerType.stdio,
          child: ListTile(
            leading: const Icon(Icons.terminal),
            title: Text('settings.mcp_add_cli_server'.tr()),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null, // Handled by PopupMenuButton.
        icon: const Icon(Icons.add),
        label: Text('settings.mcp_add_server'.tr()),
      ),
    );
  }
}
