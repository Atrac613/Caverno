import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_sink.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/model_usage_providers.dart';
import 'package:caverno/features/chat/presentation/providers/pro_reasoning_run_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

import 'support/pro_reasoning_grounded_claims_verifier.dart';

const _question =
    'Investigate which APIs llama.cpp and LM Studio expose for loaded-model or '
    'slot discovery, then recommend a safe two-host candidate placement policy. '
    'State uncertainty and keep the final answer concise.';
const _groundedClaimsQuestion =
    'Read /canary/hardware_requirements.txt and report the minimum memory '
    'requirement. Separate the verified artifact size from any runtime RAM '
    'requirement, and do not invent a safety margin.';
const _groundedClaimsEvidence = <String>[
  'Verified artifact size: 397 GB.',
  'Published runtime RAM minimum: not specified.',
  'Runtime overhead depends on the engine and deployment settings.',
];

void main() {
  final originalHttpOverrides = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = originalHttpOverrides;
  final liveEnabled =
      Platform.environment['CAVERNO_PRO_REASONING_LIVE_CANARY'] == '1';

  test(
    'Pro Reasoning closes multi-host, degradation, and cancellation paths',
    () async {
      final env = _ProLiveEnv.fromEnvironment();
      final artifactRoot = Directory(
        _requiredEnv('CAVERNO_PRO_REASONING_LIVE_CANARY_DIR'),
      );
      await artifactRoot.create(recursive: true);
      final requestedScenarios =
          (Platform.environment['CAVERNO_PRO_REASONING_SCENARIOS'] ??
                  'multi_host,selected_endpoint,single_host,cancel')
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
      final evidence = <Map<String, dynamic>>[];

      for (final scenario in requestedScenarios) {
        if (!const {
          'multi_host',
          'selected_endpoint',
          'single_host',
          'cancel',
          'logging_disabled',
          'grounded_claims',
        }.contains(scenario)) {
          throw StateError('Unsupported Pro Reasoning scenario: $scenario');
        }
        final result = await _runScenario(
          scenario: scenario,
          env: env,
          artifactRoot: artifactRoot,
        );
        evidence.add(result);
        await File('${artifactRoot.path}/canary_evidence.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'schema': 'caverno_pro_reasoning_live_canary_evidence',
            'version': 1,
            'generatedAt': DateTime.now().toUtc().toIso8601String(),
            'scenarios': evidence,
          }),
          flush: true,
        );
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_PRO_REASONING_LIVE_CANARY=1 and endpoint variables to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<Map<String, dynamic>> _runScenario({
  required String scenario,
  required _ProLiveEnv env,
  required Directory artifactRoot,
}) async {
  final includeSecondary = const {
    'multi_host',
    'selected_endpoint',
  }.contains(scenario);
  final question = scenario == 'grounded_claims'
      ? _groundedClaimsQuestion
      : _question;
  final toolService = scenario == 'grounded_claims'
      ? _GroundedClaimsToolService()
      : _NoToolsMcpToolService();
  final settings = env.settings(
    includeSecondary: includeSecondary,
    selectSecondary: scenario == 'selected_endpoint',
    candidateRouting: scenario == 'selected_endpoint'
        ? ProReasoningCandidateRouting.selectedOnly
        : ProReasoningCandidateRouting.mesh,
  );
  final logRoot = Directory('${artifactRoot.path}/$scenario/session_logs');
  final usageSink = _RecordingModelUsageSink();
  final container = _buildContainer(
    settings: settings,
    logStore: LlmSessionLogStore(rootDirectoryProvider: () async => logRoot),
    usageSink: usageSink,
    toolService: toolService,
  );
  final stages = <String>[];
  final endpointLabels = <String>{};
  DateTime? cancelTriggeredAt;
  Timer? cancelTimer;
  late final ProReasoningRunNotifier notifier;
  final subscription = container.listen<ProReasoningRunState>(
    proReasoningRunProvider,
    (_, next) {
      final progress = next.progress;
      if (progress == null) return;
      stages.add(progress.stage.name);
      endpointLabels.addAll(progress.endpointLabels);
      if (scenario == 'cancel' &&
          progress.stage == ProReasoningStage.explore &&
          progress.completedCandidates >= 1 &&
          cancelTimer == null) {
        cancelTimer = Timer(const Duration(milliseconds: 25), () {
          cancelTriggeredAt = DateTime.now();
          notifier.cancel();
        });
      }
    },
    fireImmediately: true,
  );

  final startedAt = DateTime.now();
  try {
    notifier = container.read(proReasoningRunProvider.notifier);
    final completed = await notifier.start(
      question,
      depth: ProReasoningDepth.standard,
    );
    final finishedAt = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    expect(completed, isTrue, reason: _diagnostic(container, stages));
    expect(conversation, isNotNull, reason: _diagnostic(container, stages));
    final messages = conversation!.messages;
    expect(
      messages.where(
        (message) =>
            message.role == MessageRole.user && message.content == question,
      ),
      hasLength(1),
      reason: _diagnostic(container, stages),
    );
    final assistantAnswers = messages
        .where(
          (message) =>
              message.role == MessageRole.assistant &&
              !message.isStreaming &&
              message.content.trim().isNotEmpty,
        )
        .toList(growable: false);
    expect(
      assistantAnswers,
      isNotEmpty,
      reason: _diagnostic(container, stages),
    );

    final entries = _readLogEntries(logRoot);
    final proEntries = entries
        .where(
          (entry) => (entry['operation']?.toString() ?? '').startsWith(
            'pro_reasoning_',
          ),
        )
        .toList(growable: false);
    final operations = proEntries
        .map((entry) => entry['operation']?.toString() ?? '')
        .toSet();
    expect(usageSink.records, isNotEmpty);
    expect(
      usageSink.records.every(
        (record) => record.role == ModelUsageRole.proReasoning,
      ),
      isTrue,
    );

    if (scenario == 'logging_disabled') {
      expect(proEntries, isEmpty);
      final result = <String, dynamic>{
        'scenario': scenario,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'finishedAt': finishedAt.toUtc().toIso8601String(),
        'durationMs': finishedAt.difference(startedAt).inMilliseconds,
        'conversationId': conversation.id,
        'visibleUserMessages': messages
            .where((message) => message.role == MessageRole.user)
            .length,
        'assistantMessages': assistantAnswers.length,
        'progressStages': stages.toSet().toList(growable: false),
        'progressEndpoints': endpointLabels.toList(growable: false),
        'operations': const <String>[],
        'usageRoles': usageSink.records
            .map((record) => record.role.name)
            .toSet()
            .toList(growable: false),
        'sessionLoggingDisabled': true,
      };
      stdout.writeln('PRO_REASONING_CANARY ${jsonEncode(result)}');
      return result;
    }

    expect(operations, contains('pro_reasoning_frame'));
    expect(operations, contains('pro_reasoning_candidate'));
    expect(operations, contains('pro_reasoning_synthesis'));
    expect(operations, contains('pro_reasoning_summary'));
    final conversationIds = proEntries
        .map((entry) => entry['context'])
        .whereType<Map>()
        .map((context) => context['conversationId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    expect(conversationIds, {conversation.id});

    final summaryEntry = proEntries.lastWhere(
      (entry) => entry['operation'] == 'pro_reasoning_summary',
    );
    final response = Map<String, dynamic>.from(summaryEntry['response'] as Map);
    final summary = Map<String, dynamic>.from(
      jsonDecode(response['content'] as String) as Map,
    );
    final summaryEndpoints = (summary['endpoints'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final candidateCount = (summary['candidates'] as num?)?.toInt() ?? 0;
    final candidateEntries = proEntries
        .where((entry) => entry['operation'] == 'pro_reasoning_candidate')
        .toList(growable: false);

    Map<String, dynamic>? groundedClaims;
    if (scenario == 'grounded_claims') {
      final answer = assistantAnswers.last.content;
      final normalized = answer.toLowerCase();
      const verifier = ProReasoningGroundedClaimsVerifier();
      final supportedMemoryClaims = verifier.memoryClaims(
        _groundedClaimsEvidence.join('\n'),
      );
      final observedMemoryClaims = verifier.memoryClaims(answer);
      final unsupportedMemoryClaims = verifier.unsupportedMemoryClaims(
        evidence: _groundedClaimsEvidence.join('\n'),
        answer: answer,
      );
      expect(toolService.executedToolNames, contains('read_file'));
      expect(answer, contains('397'));
      expect(
        unsupportedMemoryClaims,
        isEmpty,
        reason:
            'Final answer introduced unsupported memory quantities: '
            '$unsupportedMemoryClaims\n$answer',
      );
      expect(
        normalized,
        anyOf(
          contains('not specified'),
          contains('not provided'),
          contains('unknown'),
          contains('cannot be determined'),
          contains('insufficient'),
        ),
        reason:
            'Final answer did not preserve the missing RAM requirement:\n$answer',
      );
      groundedClaims = <String, dynamic>{
        'toolCalls': toolService.executedToolNames,
        'mentionsArtifactSize': answer.contains('397'),
        'supportedMemoryClaims': supportedMemoryClaims,
        'observedMemoryClaims': observedMemoryClaims,
        'unsupportedMemoryClaims': unsupportedMemoryClaims,
        'preservesMissingRuntimeRequirement': true,
      };
    }

    if (scenario == 'multi_host') {
      expect(summaryEndpoints.toSet().length, greaterThanOrEqualTo(2));
      expect(candidateCount, greaterThanOrEqualTo(2));
      expect(summary['cancelRequested'], isFalse);
    } else if (scenario == 'selected_endpoint') {
      expect(summary['candidateRouting'], 'selectedOnly');
      expect(summaryEndpoints.toSet(), {env.secondary.label});
      expect(candidateCount, greaterThanOrEqualTo(1));
      expect(candidateEntries, isNotEmpty);
      for (final entry in candidateEntries) {
        final request = Map<String, dynamic>.from(entry['request'] as Map);
        expect(request['model'], env.secondary.model);
        final messages = (request['messages'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList(growable: false);
        final metadata = messages.firstWhere(
          (message) =>
              message['id'].toString().startsWith('pro_reasoning_candidate_'),
        );
        final decoded = Map<String, dynamic>.from(
          jsonDecode(metadata['content'] as String) as Map,
        );
        expect(decoded['endpointId'], env.secondary.id);
        expect(decoded['endpointLabel'], env.secondary.label);
      }
    } else {
      expect(summaryEndpoints.toSet().length, 1);
    }
    if (scenario == 'cancel') {
      expect(cancelTriggeredAt, isNotNull);
      expect(summary['cancelRequested'], isTrue);
      expect(candidateCount, greaterThanOrEqualTo(1));
      expect(
        finishedAt.difference(cancelTriggeredAt!),
        lessThan(const Duration(seconds: 30)),
      );
    }

    final result = <String, dynamic>{
      'scenario': scenario,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'finishedAt': finishedAt.toUtc().toIso8601String(),
      'durationMs': finishedAt.difference(startedAt).inMilliseconds,
      'conversationId': conversation.id,
      'visibleUserMessages': messages
          .where((message) => message.role == MessageRole.user)
          .length,
      'assistantMessages': assistantAnswers.length,
      'progressStages': stages.toSet().toList(growable: false),
      'progressEndpoints': endpointLabels.toList(growable: false),
      'operations': operations.toList(growable: false)..sort(),
      'usageRoles': usageSink.records
          .map((record) => record.role.name)
          .toSet()
          .toList(growable: false),
      'summary': summary,
      'groundedClaims': ?groundedClaims,
    };
    stdout.writeln('PRO_REASONING_CANARY ${jsonEncode(result)}');
    return result;
  } finally {
    cancelTimer?.cancel();
    subscription.close();
    container.dispose();
  }
}

ProviderContainer _buildContainer({
  required AppSettings settings,
  required LlmSessionLogStore logStore,
  required ModelUsageSink usageSink,
  required _NoToolsMcpToolService toolService,
}) {
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _LiveSettingsNotifier(settings),
      ),
      conversationRepositoryProvider.overrideWithValue(
        _InMemoryConversationRepository(),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(
        ChatRemoteDataSource(
          baseUrl: settings.baseUrl,
          apiKey: settings.apiKey,
          usageSink: usageSink,
        ),
      ),
      modelUsageSinkProvider.overrideWithValue(usageSink),
      llmSessionLogStoreProvider.overrideWithValue(logStore),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(
        _ForegroundAppLifecycleService(),
      ),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

List<Map<String, dynamic>> _readLogEntries(Directory root) {
  if (!root.existsSync()) return const [];
  final entries = <Map<String, dynamic>>[];
  for (final file
      in root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.jsonl'))) {
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is Map) entries.add(Map<String, dynamic>.from(decoded));
    }
  }
  return entries;
}

String _diagnostic(ProviderContainer container, List<String> stages) {
  final run = container.read(proReasoningRunProvider);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  return [
    'isRunning=${run.isRunning}',
    'error=${run.error}',
    'stage=${run.progress?.stage.name}',
    'observedStages=${stages.join(',')}',
    'messages=${conversation?.messages.map((message) => '${message.role.name}:${message.content}').join(' | ')}',
  ].join('\n');
}

final class _ProLiveEnv {
  const _ProLiveEnv({required this.primary, required this.secondary});

  final _EndpointEnv primary;
  final _EndpointEnv secondary;

  factory _ProLiveEnv.fromEnvironment() => _ProLiveEnv(
    primary: _EndpointEnv(
      id: 'pro-canary-primary',
      label: 'primary-host',
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
    ),
    secondary: _EndpointEnv(
      id: 'pro-canary-secondary',
      label: 'secondary-host',
      baseUrl: _requiredEnv('CAVERNO_PRO_REASONING_SECONDARY_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_PRO_REASONING_SECONDARY_API_KEY'),
      model: _requiredEnv('CAVERNO_PRO_REASONING_SECONDARY_MODEL'),
    ),
  );

  AppSettings settings({
    required bool includeSecondary,
    bool selectSecondary = false,
    ProReasoningCandidateRouting candidateRouting =
        ProReasoningCandidateRouting.mesh,
  }) {
    final endpoints = <LlmEndpoint>[
      primary.toSettings(),
      if (includeSecondary) secondary.toSettings(),
    ];
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      baseUrl: primary.baseUrl,
      apiKey: primary.apiKey,
      model: primary.model,
      llmEndpoints: endpoints,
      activeLlmEndpointId: primary.id,
      proReasoningEnabled: true,
      proReasoningDepth: ProReasoningDepth.standard,
      proReasoningCandidateRouting: candidateRouting,
      proReasoningModel: selectSecondary ? secondary.model : primary.model,
      proReasoningEndpointId: selectSecondary ? secondary.id : primary.id,
      temperature: 0.1,
      maxTokens: 2048,
      mcpEnabled: false,
      enableLlmSessionLogs: true,
      demoMode: false,
    );
  }
}

final class _EndpointEnv {
  const _EndpointEnv({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String apiKey;
  final String model;

  LlmEndpoint toSettings() => LlmEndpoint(
    id: id,
    label: label,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
  );
}

final class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.settings);

  final AppSettings settings;

  @override
  AppSettings build() => settings;
}

final class _UsageRecord {
  const _UsageRecord({required this.role});

  final ModelUsageRole role;
}

final class _RecordingModelUsageSink implements ModelUsageSink {
  final records = <_UsageRecord>[];

  @override
  void record({
    required String model,
    required String endpointId,
    required ModelUsageRole role,
    required TokenUsage usage,
    required int durationMs,
    String? label,
    String? finishReason,
    bool isError = false,
  }) {
    records.add(_UsageRecord(role: role));
  }
}

final class _InMemoryConversationRepository
    implements ConversationRepositoryApi {
  final _conversations = <String, Conversation>{};

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
  Future<List<Conversation>> search(String query) async => const [];
}

class _NoToolsMcpToolService extends McpToolService {
  final executedToolNames = <String>[];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => const [];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'Tool is not available'}),
      isSuccess: false,
      errorMessage: 'Tool is not available',
    );
  }
}

final class _GroundedClaimsToolService extends _NoToolsMcpToolService {
  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => const [
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Read the controlled hardware evidence file.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
        },
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    if (name != 'read_file') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported tool: $name'}),
        isSuccess: false,
        errorMessage: 'Unsupported tool: $name',
      );
    }
    return McpToolResult(
      toolName: name,
      result: jsonEncode({
        'path': '/canary/hardware_requirements.txt',
        'content': _groundedClaimsEvidence.join('\n'),
      }),
      isSuccess: true,
    );
  }
}

final class _MockMemoryBox extends Mock implements Box<String> {}

final class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

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

final class _ForegroundAppLifecycleService extends AppLifecycleService {
  @override
  bool get isInBackground => false;
}

final class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}
}

final class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the Pro Reasoning live canary.');
  }
  return value;
}
