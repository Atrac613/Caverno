import 'dart:async';

import 'package:caverno/core/services/ble_service.dart';
import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/serial_port_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PendingToolApprovalRegistry device and participant requests', () {
    test('cancels every P5c request with its safe value', () async {
      final registry = PendingToolApprovalRegistry();
      final owner = _owner('conversation-a', 1);
      final computerUse = _computerUse(owner: owner, id: 'computer-use-1');
      final browser = _browser(owner: owner, id: 'browser-1');
      final ble = _ble(owner: owner, id: 'ble-1');
      final serial = _serial(owner: owner, id: 'serial-1');
      final participant = _participant(owner: owner, id: 'participant-1');
      for (final request in <PendingToolApproval<dynamic>>[
        computerUse,
        browser,
        ble,
        serial,
        participant,
      ]) {
        registry.register(request);
      }

      expect(registry.cancelOwner(owner), hasLength(5));

      final computerDecision = await computerUse.completer.future;
      expect(computerDecision.approved, isFalse);
      expect(computerDecision.armed, isFalse);
      expect(computerDecision.blockerCode, 'approval_denied');
      expect(await browser.completer.future, isFalse);
      expect(await ble.completer.future, isFalse);
      expect(await serial.completer.future, isFalse);
      expect(await participant.completer.future, isFalse);
      expect(registry.isEmpty, isTrue);
    });

    test('isolates conversations with the same generation', () async {
      final registry = PendingToolApprovalRegistry();
      final ownerA = _owner('conversation-a', 7);
      final ownerB = _owner('conversation-b', 7);
      final browser = _browser(owner: ownerA, id: 'browser-a');
      final ble = _ble(owner: ownerB, id: 'ble-b');
      registry
        ..register(browser)
        ..register(ble);

      expect(
        registry.take<PendingBrowserAction>(owner: ownerB, id: browser.id),
        isNull,
      );
      expect(registry.cancelOwner(ownerA), [same(browser)]);

      expect(await browser.completer.future, isFalse);
      expect(ble.completer.isCompleted, isFalse);
      expect(registry.find<PendingBleConnect>(ble.id), same(ble));
      expect(registry.cancel(owner: ownerB, id: ble.id), isTrue);
      expect(await ble.completer.future, isFalse);
    });

    test('rejects a stale owner without disturbing its successor', () async {
      final registry = PendingToolApprovalRegistry();
      final staleOwner = _owner('conversation-a', 3);
      final successorOwner = _owner('conversation-a', 4);
      final stale = _serial(owner: staleOwner, id: 'serial-stale');
      final successor = _participant(
        owner: successorOwner,
        id: 'participant-current',
      );
      final cleared = <String>[];
      registry
        ..register(stale)
        ..register(successor);

      expect(
        registry.takeCurrent<PendingSerialOpen>(
          id: stale.id,
          ownerIsCurrent: (owner) => owner == successorOwner,
          clear: (request) => cleared.add(request.id),
        ),
        isNull,
      );

      expect(await stale.completer.future, isFalse);
      expect(cleared, [stale.id]);
      expect(
        registry.find<PendingParticipantToolApproval>(successor.id),
        same(successor),
      );
      expect(successor.completer.isCompleted, isFalse);

      final current = registry.takeCurrent<PendingParticipantToolApproval>(
        id: successor.id,
        ownerIsCurrent: (owner) => owner == successorOwner,
        clear: (request) => cleared.add(request.id),
      );
      expect(current, same(successor));
      current!.completer.complete(true);
      expect(await successor.completer.future, isTrue);
      expect(cleared, [stale.id, successor.id]);
      expect(registry.isEmpty, isTrue);
    });

    test(
      'preserves global indexes across duplicate and type failures',
      () async {
        final registry = PendingToolApprovalRegistry();
        final ownerA = _owner('conversation-a', 1);
        final ownerB = _owner('conversation-b', 1);
        final original = _browser(owner: ownerA, id: 'shared-id');
        final duplicate = _ble(owner: ownerB, id: 'shared-id');
        registry.register(original);

        expect(() => registry.register(duplicate), throwsA(isA<StateError>()));
        expect(
          registry.take<PendingSerialOpen>(owner: ownerA, id: original.id),
          isNull,
        );
        expect(
          registry.find<PendingBrowserAction>(original.id),
          same(original),
        );
        expect(duplicate.completer.isCompleted, isFalse);

        expect(
          registry.take<PendingBrowserAction>(owner: ownerA, id: original.id),
          same(original),
        );
        expect(registry.find<PendingBrowserAction>(original.id), isNull);
        expect(registry.isEmpty, isTrue);

        registry.register(duplicate);
        expect(registry.find<PendingBleConnect>(duplicate.id), same(duplicate));
        expect(registry.cancelAll(), 1);
        expect(await duplicate.completer.future, isFalse);
        expect(registry.find<PendingBleConnect>(duplicate.id), isNull);
        expect(registry.cancelAll(), 0);
      },
    );
  });

  test(
    'approved browser action cannot execute after synchronous clear',
    () async {
      final repository = _InMemoryConversationRepository();
      final dataSource = _SingleApprovalToolDataSource(
        ToolCallInfo(
          id: 'browser-action-1',
          name: 'browser_click',
          arguments: const {'ref': 7, 'reason': 'Open the selected result.'},
        ),
      );
      final toolService = _CountingApprovalToolService('browser_click');
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _BrowserPoisonSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _NoopSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatNotifierProvider.notifier);
      final send = notifier.sendMessage('Click the result.');
      await _waitUntil(() => notifier.state.pendingBrowserAction != null);
      final pending = notifier.state.pendingBrowserAction!;

      expect(
        notifier.resolveBrowserAction(id: pending.id, approved: true),
        isTrue,
      );
      notifier.clearMessages();
      await send.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, isEmpty);
      expect(
        notifier.resolveBrowserAction(id: pending.id, approved: true),
        isFalse,
      );
      expect(notifier.state.pendingBrowserAction, isNull);
    },
  );

  test(
    'expired blocked Computer Use approval records no audit or denial',
    () async {
      MacosComputerUseAuditLog.instance.clear();
      addTearDown(MacosComputerUseAuditLog.instance.clear);
      final repository = _InMemoryConversationRepository();
      final dataSource = _SingleApprovalToolDataSource(
        ToolCallInfo(
          id: 'computer-action-1',
          name: 'computer_click',
          arguments: const {
            'x': 80,
            'y': 120,
            'target': {
              'label': 'Delete workspace',
              'role': 'button',
              'action': 'delete',
              'risk': 'destructive',
            },
          },
        ),
      );
      final toolService = _CountingApprovalToolService('computer_click');
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _BrowserPoisonSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _NoopSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatNotifierProvider.notifier);
      final send = notifier.sendMessage('Click the destructive control.');
      await _waitUntil(() => notifier.state.pendingComputerUseAction != null);
      final pending = notifier.state.pendingComputerUseAction!;
      expect(
        pending.approvalBlockerCodes,
        contains('destructive_target_blocked'),
      );

      expect(
        notifier.resolveComputerUseAction(
          id: pending.id,
          approved: true,
          armed: true,
        ),
        isTrue,
      );
      notifier.clearMessages();
      await send.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, isEmpty);
      expect(MacosComputerUseAuditLog.instance.redactedEntries, isEmpty);
      expect(
        notifier.resolveComputerUseAction(
          id: pending.id,
          approved: true,
          armed: true,
        ),
        isFalse,
      );
    },
  );

  test(
    'expired in-flight Computer Use action skips follow-up observation',
    () async {
      MacosComputerUseAuditLog.instance.clear();
      addTearDown(MacosComputerUseAuditLog.instance.clear);
      final repository = _InMemoryConversationRepository();
      final dataSource = _SingleApprovalToolDataSource(
        ToolCallInfo(
          id: 'computer-action-in-flight',
          name: 'computer_click',
          arguments: const {
            'x': 80,
            'y': 120,
            'target': {'label': 'Save', 'role': 'button', 'action': 'save'},
          },
        ),
      );
      final toolService = _BlockingComputerUseToolService();
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _BrowserPoisonSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _NoopSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatNotifierProvider.notifier);
      final send = notifier.sendMessage('Click the Save control.');
      await _waitUntil(() => notifier.state.pendingComputerUseAction != null);
      final pending = notifier.state.pendingComputerUseAction!;

      expect(
        notifier.resolveComputerUseAction(
          id: pending.id,
          approved: true,
          armed: true,
        ),
        isTrue,
      );
      await toolService.actionStarted.future.timeout(
        const Duration(seconds: 5),
      );
      notifier.clearMessages();
      toolService.releaseAction.complete();
      await send.timeout(const Duration(seconds: 5));

      expect(toolService.executedToolNames, ['computer_click']);
      expect(
        toolService.executedToolNames,
        isNot(contains('computer_vision_observe')),
      );
    },
  );

  test(
    'expired BLE connect is disconnected after the in-flight call',
    () async {
      final repository = _InMemoryConversationRepository();
      final dataSource = _SingleApprovalToolDataSource(
        ToolCallInfo(
          id: 'ble-connect-1',
          name: 'ble_connect',
          arguments: const {
            'device_id': 'device-1',
            'reason': 'Connect to the sensor.',
          },
        ),
      );
      final toolService = _CountingApprovalToolService('ble_connect');
      final bleService = _BlockingBleService();
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _BrowserPoisonSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _NoopSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          bleServiceProvider.overrideWithValue(bleService),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatNotifierProvider.notifier);
      final send = notifier.sendMessage('Connect to the sensor.');
      await _waitUntil(() => notifier.state.pendingBleConnect != null);
      final pending = notifier.state.pendingBleConnect!;

      expect(
        notifier.resolveBleConnect(id: pending.id, approved: true),
        isTrue,
      );
      await bleService.connectStarted.future.timeout(
        const Duration(seconds: 5),
      );
      notifier.clearMessages();
      bleService.releaseConnect.complete();
      await send.timeout(const Duration(seconds: 5));

      expect(bleService.connectedDeviceIds, ['device-1']);
      expect(bleService.disconnectedDeviceIds, ['device-1']);
      expect(toolService.executedToolNames, isEmpty);
    },
  );

  test('expired BLE attempt preserves a connection that predates it', () async {
    final repository = _InMemoryConversationRepository();
    final dataSource = _SingleApprovalToolDataSource(
      ToolCallInfo(
        id: 'ble-connect-preexisting',
        name: 'ble_connect',
        arguments: const {
          'device_id': 'device-1',
          'reason': 'Reuse the connected sensor.',
        },
      ),
    );
    final toolService = _CountingApprovalToolService('ble_connect');
    final bleService = _BlockingBleService(initiallyConnected: true);
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _BrowserPoisonSettingsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(repository),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _NoopSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        bleServiceProvider.overrideWithValue(bleService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);
    final send = notifier.sendMessage('Reuse the connected sensor.');
    await _waitUntil(() => notifier.state.pendingBleConnect != null);
    final pending = notifier.state.pendingBleConnect!;

    expect(notifier.resolveBleConnect(id: pending.id, approved: true), isTrue);
    await bleService.connectStarted.future.timeout(const Duration(seconds: 5));
    notifier.clearMessages();
    bleService.releaseConnect.complete();
    await send.timeout(const Duration(seconds: 5));

    expect(bleService.connectedDeviceIds, ['device-1']);
    expect(bleService.disconnectedDeviceIds, isEmpty);
    expect(bleService.getConnectionState('device-1'), 'connected');
  });

  test('expired BLE attempt rolls back before a successor connects', () async {
    final repository = _InMemoryConversationRepository();
    final dataSource = _SingleApprovalToolDataSource(
      ToolCallInfo(
        id: 'ble-connect-shared-device',
        name: 'ble_connect',
        arguments: const {
          'device_id': 'device-1',
          'reason': 'Connect the shared sensor.',
        },
      ),
    );
    final toolService = _CountingApprovalToolService('ble_connect');
    final bleService = _SequentialBlockingBleService();
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _BrowserPoisonSettingsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(repository),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _NoopSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        bleServiceProvider.overrideWithValue(bleService),
      ],
    );
    addTearDown(container.dispose);
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation();
    final ownerAConversation = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    conversations.createNewConversation();
    final ownerBConversation = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    conversations.selectConversation(ownerAConversation);
    final notifier = container.read(chatNotifierProvider.notifier);

    final sendA = notifier.sendMessage('Connect owner A.');
    await _waitUntil(() => notifier.state.pendingBleConnect != null);
    final pendingA = notifier.state.pendingBleConnect!;
    expect(notifier.resolveBleConnect(id: pendingA.id, approved: true), isTrue);
    await bleService.firstConnectStarted.future.timeout(
      const Duration(seconds: 5),
    );

    conversations.selectConversation(ownerBConversation);
    await Future<void>.delayed(Duration.zero);
    final sendB = notifier.sendMessage('Connect owner B.');
    await _waitUntil(() => notifier.state.pendingBleConnect != null);
    final pendingB = notifier.state.pendingBleConnect!;
    expect(notifier.resolveBleConnect(id: pendingB.id, approved: true), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(bleService.secondConnectStarted.isCompleted, isFalse);

    conversations.selectConversation(ownerAConversation);
    await Future<void>.delayed(Duration.zero);
    notifier.cancelStreaming();
    bleService.releaseFirstConnect.complete();
    await sendA.timeout(const Duration(seconds: 5));
    await bleService.secondConnectStarted.future.timeout(
      const Duration(seconds: 5),
    );
    bleService.releaseSecondConnect.complete();
    await sendB.timeout(const Duration(seconds: 5));

    expect(bleService.connectedDeviceIds, ['device-1', 'device-1']);
    expect(bleService.disconnectedDeviceIds, ['device-1']);
    expect(bleService.getConnectionState('device-1'), 'connected');
  });

  test('expired serial open is closed after the in-flight call', () async {
    final repository = _InMemoryConversationRepository();
    final dataSource = _SingleApprovalToolDataSource(
      ToolCallInfo(
        id: 'serial-open-1',
        name: 'serial_open',
        arguments: const {
          'port': '/dev/tty.test',
          'baud_rate': 115200,
          'reason': 'Open the test port.',
        },
      ),
    );
    final toolService = _CountingApprovalToolService('serial_open');
    final serialService = _BlockingSerialPortService();
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _BrowserPoisonSettingsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(repository),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _NoopSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        serialPortServiceProvider.overrideWithValue(serialService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);
    final send = notifier.sendMessage('Open the test serial port.');
    await _waitUntil(() => notifier.state.pendingSerialOpen != null);
    final pending = notifier.state.pendingSerialOpen!;

    expect(notifier.resolveSerialOpen(id: pending.id, approved: true), isTrue);
    await serialService.openStarted.future.timeout(const Duration(seconds: 5));
    notifier.clearMessages();
    serialService.releaseOpen.complete();
    await send.timeout(const Duration(seconds: 5));

    expect(serialService.openedPorts, ['/dev/tty.test']);
    expect(serialService.closedPorts, ['/dev/tty.test']);
    expect(toolService.executedToolNames, isEmpty);
  });
}

ChatTurnOwner _owner(String conversationId, int generation) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

PendingComputerUseAction _computerUse({
  required ChatTurnOwner owner,
  required String id,
}) {
  return PendingComputerUseAction(
    owner: owner,
    id: id,
    toolName: 'macos_click',
    title: 'Click a control',
    riskCategory: 'input',
    riskLabel: 'Computer control',
    warningMessage: 'This action controls the computer.',
    approveLabel: 'Click',
    requiresUserApproval: true,
    requiresSmokeArming: false,
    emergencyStop: false,
    summary: 'Click the target control',
    details: const ['Target: Save'],
    targetSummary: 'Save button',
    targetDetails: const ['Window: Editor'],
    exactTextPreview: null,
    exactTextLength: null,
    approvalBoundaries: const ['One click'],
    approvalBlockerCodes: const [],
    actionProposalNextAction: null,
    visionObservationSummary: null,
    visionObservationDetails: const [],
    reason: 'Save the document',
    completer: Completer<ComputerUseActionApprovalDecision>(),
  );
}

PendingBrowserAction _browser({
  required ChatTurnOwner owner,
  required String id,
}) {
  return PendingBrowserAction(
    owner: owner,
    id: id,
    toolName: 'browser_click',
    title: 'Click an element',
    riskLabel: 'Browser interaction',
    warningMessage: 'This action changes the current page.',
    approveLabel: 'Click',
    summary: 'Click the result',
    details: const ['Element: #7'],
    targetSummary: 'Search result',
    sensitiveValuePreview: null,
    reason: 'Open the result',
    completer: Completer<bool>(),
  );
}

PendingBleConnect _ble({required ChatTurnOwner owner, required String id}) {
  return PendingBleConnect(
    owner: owner,
    id: id,
    deviceId: 'device-1',
    deviceName: 'Sensor',
    completer: Completer<bool>(),
  );
}

PendingSerialOpen _serial({required ChatTurnOwner owner, required String id}) {
  return PendingSerialOpen(
    owner: owner,
    id: id,
    portName: '/dev/tty.test',
    baudRate: 115200,
    completer: Completer<bool>(),
  );
}

PendingParticipantToolApproval _participant({
  required ChatTurnOwner owner,
  required String id,
}) {
  return PendingParticipantToolApproval(
    owner: owner,
    id: id,
    participantId: 'participant-1',
    participantName: 'Reviewer',
    participantRoleLabel: 'Code reviewer',
    toolName: 'read_file',
    arguments: const {'path': 'lib/main.dart'},
    reason: 'Inspect the entrypoint',
    completer: Completer<bool>(),
  );
}

class _BrowserPoisonSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.general,
    mcpEnabled: true,
    browserToolsEnabled: true,
    demoMode: false,
    enableLlmSessionLogs: false,
  );
}

class _InMemoryConversationRepository implements ConversationRepositoryApi {
  final Map<String, Conversation> _conversations = {};

  @override
  List<Conversation> getAll() => _conversations.values.toList(growable: false);

  @override
  Conversation? getById(String id) => _conversations[id];

  @override
  Future<Conversation?> refresh(String id) async => _conversations[id];

  @override
  Future<void> save(Conversation conversation) async {
    _conversations[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _conversations.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _conversations.clear();
  }

  @override
  Future<List<Conversation>> search(String query) async => getAll();
}

class _NoopChatMemoryRepository implements ChatMemoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(_NoopChatMemoryRepository());

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) => null;

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async => const MemoryUpdateResult.none();

  @override
  UserMemoryProfile loadProfile() => UserMemoryProfile.empty();
}

class _CountingApprovalToolService extends McpToolService {
  _CountingApprovalToolService(this.toolName);

  final String toolName;
  final List<String> executedToolNames = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': toolName,
        'description': 'Exercise an approval-owned tool.',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    return McpToolResult(toolName: name, result: 'executed', isSuccess: true);
  }
}

class _BlockingComputerUseToolService extends _CountingApprovalToolService {
  _BlockingComputerUseToolService() : super('computer_click');

  final Completer<void> actionStarted = Completer<void>();
  final Completer<void> releaseAction = Completer<void>();

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    if (name == 'computer_click') {
      actionStarted.complete();
      await releaseAction.future;
    }
    return McpToolResult(toolName: name, result: 'executed', isSuccess: true);
  }
}

class _SingleApprovalToolDataSource implements ChatDataSource {
  _SingleApprovalToolDataSource(this.toolCall);

  final ToolCallInfo toolCall;

  ChatCompletionResult get _stop =>
      ChatCompletionResult(content: 'Stopped.', finishReason: 'stop');

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future.value(
        ChatCompletionResult(
          content: '',
          toolCalls: [toolCall],
          finishReason: 'tool_calls',
        ),
      ),
    );
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(
    Stream<String>.value('Stopped.'),
    finishReason: 'stop',
  );

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _stop;

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => Stream.value('Stopped.');

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _stop;

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _stop;
}

class _BlockingBleService extends BleService {
  _BlockingBleService({bool initiallyConnected = false})
    : _connected = initiallyConnected;

  final Completer<void> connectStarted = Completer<void>();
  final Completer<void> releaseConnect = Completer<void>();
  final List<String> connectedDeviceIds = [];
  final List<String> disconnectedDeviceIds = [];
  bool _connected;

  @override
  List<BleDiscoveredDevice> getScanResults({String? sortBy}) => const [];

  @override
  Future<void> connect(String deviceId) async {
    connectedDeviceIds.add(deviceId);
    connectStarted.complete();
    await releaseConnect.future;
    _connected = true;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectedDeviceIds.add(deviceId);
    _connected = false;
  }

  @override
  String getConnectionState(String deviceId) =>
      _connected ? 'connected' : 'disconnected';
}

class _SequentialBlockingBleService extends BleService {
  final Completer<void> firstConnectStarted = Completer<void>();
  final Completer<void> secondConnectStarted = Completer<void>();
  final Completer<void> releaseFirstConnect = Completer<void>();
  final Completer<void> releaseSecondConnect = Completer<void>();
  final List<String> connectedDeviceIds = [];
  final List<String> disconnectedDeviceIds = [];
  var _connectCount = 0;
  var _connected = false;

  @override
  List<BleDiscoveredDevice> getScanResults({String? sortBy}) => const [];

  @override
  Future<void> connect(String deviceId) async {
    connectedDeviceIds.add(deviceId);
    _connectCount += 1;
    if (_connectCount == 1) {
      firstConnectStarted.complete();
      await releaseFirstConnect.future;
    } else {
      secondConnectStarted.complete();
      await releaseSecondConnect.future;
    }
    _connected = true;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectedDeviceIds.add(deviceId);
    _connected = false;
  }

  @override
  String getConnectionState(String deviceId) =>
      _connected ? 'connected' : 'disconnected';
}

class _BlockingSerialPortService extends SerialPortService {
  final Completer<void> openStarted = Completer<void>();
  final Completer<void> releaseOpen = Completer<void>();
  final List<String> openedPorts = [];
  final List<String> closedPorts = [];

  @override
  Future<String> open(
    String portName, {
    int baudRate = 9600,
    int dataBits = 8,
    String parity = 'none',
    int stopBits = 1,
    String flowControl = 'none',
  }) async {
    openedPorts.add(portName);
    openStarted.complete();
    await releaseOpen.future;
    return '{"success":true}';
  }

  @override
  Future<String> close(String portName) async {
    closedPorts.add(portName);
    return '{"success":true}';
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}
