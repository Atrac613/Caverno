import 'package:caverno/core/services/ble_service.dart';
import 'package:caverno/core/services/browser_session_service.dart';
import 'package:caverno/core/services/lan_scan_service.dart';
import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/services/serial_port_service.dart';
import 'package:caverno/core/services/ssh_service.dart';
import 'package:caverno/core/services/wifi_service.dart';
import 'package:caverno/core/services/script_runtime/script_runtime.dart';
import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_client.dart';
import 'package:caverno/features/chat/data/datasources/mcp_stdio_client.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/data/repositories/key_value_store.dart';
import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

final class LiveLlmBenchmarkToolProfile {
  LiveLlmBenchmarkToolProfile._({
    required this.service,
    required this.clients,
    this.sshService,
    this.bleService,
    this.wifiService,
    this.lanScanService,
    this.serialPortService,
    this.browserService,
    this.scriptRuntimeRegistry,
    this.backgroundProcessTools,
    this.backgroundProcessMonitorService,
  });

  final McpToolService service;
  final List<McpClientBase> clients;
  final SshService? sshService;
  final BleService? bleService;
  final WifiService? wifiService;
  final LanScanService? lanScanService;
  final SerialPortService? serialPortService;
  final BrowserSessionService? browserService;
  final ScriptRuntimeRegistry? scriptRuntimeRegistry;
  final BackgroundProcessTools? backgroundProcessTools;
  final BackgroundProcessMonitorService? backgroundProcessMonitorService;

  static Future<LiveLlmBenchmarkToolProfile> create({
    required List<McpServerConfig> mcpServers,
    required bool includeAppToolProfile,
  }) async {
    final clients = _createMcpClients(mcpServers);
    if (!includeAppToolProfile) {
      return LiveLlmBenchmarkToolProfile._(
        service: McpToolService(mcpClients: clients),
        clients: clients,
      );
    }

    final skillRepository = SkillRepository.inMemory();
    final now = DateTime.utc(2026);
    await skillRepository.save(
      Skill(
        id: 'benchmark-catalog-skill',
        name: 'Benchmark catalog skill',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final sshService = SshService();
    final bleService = BleService();
    final wifiService = WifiService();
    final lanScanService = LanScanService();
    final serialPortService = SerialPortService();
    final browserService = BrowserSessionService()..updateEnabled(true);
    final scriptRuntimeRegistry = ScriptRuntimeRegistry(const []);
    final backgroundProcessTools = BackgroundProcessTools();
    final backgroundProcessMonitorService = BackgroundProcessMonitorService(
      tools: backgroundProcessTools,
    );

    return LiveLlmBenchmarkToolProfile._(
      service: McpToolService(
        mcpClients: clients,
        conversationRepository: const _EmptyConversationRepository(),
        memoryRepository: ChatMemoryRepository(_EmptyKeyValueStore()),
        skillRepository: skillRepository,
        sshService: sshService,
        bleService: bleService,
        wifiService: wifiService,
        lanScanService: lanScanService,
        serialPortService: serialPortService,
        computerUseService: MacosComputerUseService(),
        browserService: browserService,
        scriptRuntimeRegistry: scriptRuntimeRegistry,
        backgroundProcessTools: backgroundProcessTools,
        backgroundProcessMonitorService: backgroundProcessMonitorService,
      ),
      clients: clients,
      sshService: sshService,
      bleService: bleService,
      wifiService: wifiService,
      lanScanService: lanScanService,
      serialPortService: serialPortService,
      browserService: browserService,
      scriptRuntimeRegistry: scriptRuntimeRegistry,
      backgroundProcessTools: backgroundProcessTools,
      backgroundProcessMonitorService: backgroundProcessMonitorService,
    );
  }

  Future<void> dispose() async {
    for (final client in clients) {
      await client.dispose();
    }
    backgroundProcessMonitorService?.dispose();
    await backgroundProcessTools?.dispose();
    await scriptRuntimeRegistry?.dispose();
    browserService?.dispose();
    await serialPortService?.dispose();
    await lanScanService?.dispose();
    await wifiService?.dispose();
    await bleService?.dispose();
    await sshService?.dispose();
  }
}

List<McpClientBase> _createMcpClients(List<McpServerConfig> servers) {
  return [
    for (final server in servers)
      switch (server.type) {
        McpServerType.http => McpClient(baseUrl: server.normalizedUrl),
        McpServerType.stdio => McpStdioClient(
          command: server.normalizedCommand,
          args: server.args,
          env: server.normalizedEnv,
        ),
      },
  ];
}

final class _EmptyKeyValueStore implements KeyValueStore {
  @override
  bool get isReady => true;

  @override
  String? get(String key) => null;

  @override
  Future<void> refresh(Iterable<String> keys) async {}

  @override
  Future<void> put(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

final class _EmptyConversationRepository implements ConversationRepositoryApi {
  const _EmptyConversationRepository();

  @override
  List<Conversation> getAll() => const [];

  @override
  Conversation? getById(String id) => null;

  @override
  Future<Conversation?> refresh(String id) async => null;

  @override
  Future<void> save(Conversation conversation) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<List<Conversation>> search(String query) async => const [];
}
