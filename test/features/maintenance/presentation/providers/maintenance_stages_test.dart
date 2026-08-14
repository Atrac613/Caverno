import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/worktree_agent_task_repository.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart';
import 'package:caverno/features/chat/domain/services/repo_map_lsp_symbol_cache.dart';
import 'package:caverno/features/chat/domain/services/repo_map_precompute_cache.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_data_source_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/repo_map_precompute_cache_provider.dart';
import 'package:caverno/features/maintenance/data/ll37_objective_verdict_repository.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_verdict_record.dart';
import 'package:caverno/features/maintenance/domain/services/failure_trace_miner.dart';
import 'package:caverno/features/maintenance/domain/services/harness_proposal_service.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_verification_panel.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_vote_policy.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_verifier_fidelity_profile.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/presentation/providers/ll37_objective_verdict_history_notifier.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import 'package:caverno/features/personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PassingRunner implements PersonalEvalCaseRunner {
  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase) async {
    return const PersonalEvalCaseRunOutcome(
      verificationResult: PersonalEvalVerificationResult.passed,
    );
  }
}

class _FakeCasesNotifier extends PersonalEvalCasesNotifier {
  _FakeCasesNotifier(this._cases);
  final List<PersonalEvalCase> _cases;

  @override
  Future<List<PersonalEvalCase>> build() async => _cases;
}

class _FakeCodingProjectsNotifier extends CodingProjectsNotifier {
  _FakeCodingProjectsNotifier(this._state);
  final CodingProjectsState _state;

  @override
  CodingProjectsState build() => _state;
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this.settings);

  final AppSettings settings;

  @override
  AppSettings build() => settings;
}

class _MutableSettingsNotifier extends SettingsNotifier {
  _MutableSettingsNotifier(this.initialSettings);

  final AppSettings initialSettings;

  @override
  AppSettings build() => initialSettings;

  void replace(AppSettings settings) => state = settings;
}

class _RecordingVerifierDataSource extends ChatDataSource {
  int requestCount = 0;
  List<Message>? messages;
  List<Map<String, dynamic>>? tools;
  String? model;
  final models = <String>[];
  ModelUsageRole? usageRole;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestCount += 1;
    this.messages = messages;
    this.tools = tools;
    this.model = model;
    if (model != null) models.add(model);
    usageRole = ModelUsageRole.current;
    return ChatCompletionResult(
      content: jsonEncode({
        'verdict': 'not_refuted',
        'confidence': 1,
        'blocking': 'none',
        'findings': <Object?>[],
      }),
      finishReason: 'stop',
    );
  }

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
  }) {
    throw UnimplementedError();
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(const Stream<String>.empty());

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
  }) => const Stream<String>.empty();
}

class _FixedMcpToolService extends McpToolService {
  _FixedMcpToolService(this.definitions);

  final List<Map<String, dynamic>> definitions;

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => definitions;
}

class _FailingVerdictHistoryNotifier
    extends Ll37ObjectiveVerdictHistoryNotifier {
  @override
  List<Ll37ObjectiveVerdictRecord> build() => const [];

  @override
  Future<void> record(Ll37ObjectiveVerdictRecord record) {
    throw StateError('verdict store unavailable');
  }
}

void main() {
  // Building the provider only constructs the stage objects; the probe /
  // calibrate / eval bodies are lazy (they hit notifiers only when run), so the
  // structure and the adopt gating can be tested without LLM overrides.
  List<MaintenanceStage> stages() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(maintenanceStagesProvider);
  }

  MaintenanceStageContext context([Map<String, Object?>? shared]) =>
      MaintenanceStageContext(
        handle: IdleMaintenanceRunHandle(),
        shared: shared ?? <String, Object?>{},
      );

  test(
    'wires probe -> calibrate -> eval -> objective_verify -> mine -> propose -> adopt -> '
    'precompute -> warm_cache, warm-up last',
    () {
      expect(stages().map((s) => s.name), [
        'probe',
        'calibrate',
        'eval',
        'objective_verify',
        'mine',
        'propose',
        'adopt',
        'precompute',
        'warm_cache',
      ]);
    },
  );

  test(
    'objective_verify fails closed without an eligible fidelity profile',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final stage = container
          .read(maintenanceStagesProvider)
          .firstWhere((s) => s.name == 'objective_verify');

      final outcome = await stage.run(context());

      expect(outcome.status, MaintenanceStageStatus.skipped);
      expect(outcome.detail, contains('fidelity profile is not eligible'));
    },
  );

  test('objective_verify skips when no unattended candidate exists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        maintenanceLl37EligibleVerifierProfilesProvider.overrideWithValue(
          Ll37VerifierFidelityRegistry.acceptedProfiles,
        ),
      ],
    );
    addTearDown(container.dispose);
    final stage = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'objective_verify');

    final outcome = await stage.run(context());

    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no unattended objective candidates'));
  });

  test(
    'objective_verify persists one bounded vote and keeps reports run-local',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var requests = 0;
      const candidate = Ll37ObjectiveCandidate(
        id: 'routine-1',
        sourceSurface: Ll37ObjectiveSourceSurface.routine,
        attended: false,
        ll34OutcomeSettled: false,
        objective: 'Set enabled to true.',
        acceptanceCriteria: ['settings.json contains enabled true.'],
        changedFiles: [
          Ll37ObjectiveChangedFile(
            path: 'settings.json',
            content: '{"enabled":true}',
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          maintenanceLl37EligibleVerifierProfilesProvider.overrideWithValue(
            Ll37VerifierFidelityRegistry.acceptedProfiles,
          ),
          maintenanceLl37ObjectiveCandidateSourceProvider.overrideWithValue(
            () async => const [candidate, candidate],
          ),
          maintenanceLl37ObjectiveVerificationPanelFactoryProvider
              .overrideWithValue(
                (_) => Ll37ObjectiveVerificationPanel(
                  complete: (_, _) async {
                    requests += 1;
                    return jsonEncode({
                      'verdict': 'refuted',
                      'confidence': 1,
                      'blocking': 'contradiction',
                      'findings': [
                        {
                          'kind': 'unmet_criterion',
                          'location': 'settings.json',
                          'detail': 'enabled remains false',
                        },
                      ],
                    });
                  },
                ),
              ),
        ],
      );
      addTearDown(container.dispose);
      final shared = <String, Object?>{};
      final stage = container
          .read(maintenanceStagesProvider)
          .firstWhere((s) => s.name == 'objective_verify');

      final outcome = await stage.run(context(shared));

      expect(requests, 1);
      expect(outcome.status, MaintenanceStageStatus.completed);
      expect(outcome.detail, contains('refuted'));
      expect(outcome.detail, contains('objective vote 1/2'));
      expect(outcome.detail, contains('aggregate pending'));
      expect(outcome.detail, contains('persisted vote'));
      expect(outcome.detail, contains('evaluated first of 2'));
      final report = shared[maintenanceLl37ObjectiveVerificationReportKey];
      expect(report, isA<Ll37ObjectivePanelReport>());
      expect(
        (report! as Ll37ObjectivePanelReport).verdict?.blocking,
        Ll37ObjectiveBlocking.contradiction,
      );
      final history = container.read(
        ll37ObjectiveVerdictHistoryNotifierProvider,
      );
      expect(history, hasLength(1));
      expect(history.single.candidateId, candidate.id);
      expect(history.single.voteIndex, 1);
      expect(history.single.changedFilePaths, ['settings.json']);
      final aggregate =
          shared[maintenanceLl37ObjectiveVoteAggregateKey]
              as Ll37ObjectiveVoteAggregate;
      expect(aggregate.status, Ll37ObjectiveVoteAggregateStatus.pending);
      expect(
        prefs.getString(Ll37ObjectiveVerdictRepository.storageKey),
        isNotNull,
      );
    },
  );

  test(
    'objective_verify advances persisted slots and stops after convergence',
    () async {
      final task = _eligibleWorktreeAgentTask();
      final storedTasks = jsonEncode([task.toJson()]);
      SharedPreferences.setMockInitialValues({
        WorktreeAgentTaskRepository.storageKey: storedTasks,
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings.defaults().copyWith(
        llmProvider: LlmProvider.openAiCompatible,
        baseUrl: 'http://192.168.100.241:1234/v1',
        model: 'interactive-model-does-not-gate-the-roster',
      );
      final dataSource = _RecordingVerifierDataSource();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsNotifierProvider.overrideWith(
            () => _FixedSettingsNotifier(settings),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        ],
      );
      addTearDown(container.dispose);
      final stage = container
          .read(maintenanceStagesProvider)
          .firstWhere((s) => s.name == 'objective_verify');

      final first = await stage.run(context());

      expect(first.status, MaintenanceStageStatus.completed);
      expect(first.detail, contains('objective vote 1/2'));
      expect(dataSource.requestCount, 1);
      expect(dataSource.tools, isEmpty);
      expect(dataSource.model, 'qwen3.6-35b-a3b-vision');
      expect(dataSource.usageRole, ModelUsageRole.eval);
      expect(
        prefs.getString(WorktreeAgentTaskRepository.storageKey),
        storedTasks,
      );
      expect(
        prefs.getString(Ll37ObjectiveVerdictRepository.storageKey),
        isNotNull,
      );

      final secondContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsNotifierProvider.overrideWith(
            () => _FixedSettingsNotifier(settings),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        ],
      );
      addTearDown(secondContainer.dispose);
      final secondStage = secondContainer
          .read(maintenanceStagesProvider)
          .firstWhere((stage) => stage.name == 'objective_verify');

      final second = await secondStage.run(context());

      expect(second.status, MaintenanceStageStatus.completed);
      expect(second.detail, contains('objective vote 2/2'));
      expect(second.detail, contains('converged/notRefuted'));
      expect(dataSource.requestCount, 2);
      expect(dataSource.models, [
        'qwen3.6-35b-a3b-vision',
        'qwen3.6-27b-vision',
      ]);
      expect(
        secondContainer
            .read(ll37ObjectiveVerdictHistoryNotifierProvider)
            .map((record) => record.voteIndex)
            .toSet(),
        {1, 2},
      );

      final thirdContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsNotifierProvider.overrideWith(
            () => _FixedSettingsNotifier(settings),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        ],
      );
      addTearDown(thirdContainer.dispose);
      final third = await thirdContainer
          .read(maintenanceStagesProvider)
          .firstWhere((item) => item.name == 'objective_verify')
          .run(context());

      expect(third.status, MaintenanceStageStatus.skipped);
      expect(third.detail, contains('require another vote'));
      expect(dataSource.requestCount, 2);
    },
  );

  test('objective_verify fails closed when the endpoint drifts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.defaults().copyWith(
      llmProvider: LlmProvider.openAiCompatible,
      baseUrl: 'http://192.168.100.241:1234/v1',
    );
    late _MutableSettingsNotifier settingsNotifier;
    final dataSource = _RecordingVerifierDataSource();
    const candidate = Ll37ObjectiveCandidate(
      id: 'endpoint-drift',
      sourceSurface: Ll37ObjectiveSourceSurface.routine,
      attended: false,
      ll34OutcomeSettled: false,
      objective: 'Set enabled to true.',
      acceptanceCriteria: ['settings.json contains enabled true.'],
      changedFiles: [
        Ll37ObjectiveChangedFile(
          path: 'settings.json',
          content: '{"enabled":true}',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsNotifierProvider.overrideWith(() {
          settingsNotifier = _MutableSettingsNotifier(settings);
          return settingsNotifier;
        }),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        maintenanceLl37ObjectiveCandidateSourceProvider.overrideWithValue(
          () async {
            settingsNotifier.replace(
              settings.copyWith(baseUrl: 'http://192.168.100.242:1234/v1'),
            );
            return const [candidate];
          },
        ),
      ],
    );
    addTearDown(container.dispose);
    final stage = container
        .read(maintenanceStagesProvider)
        .firstWhere((item) => item.name == 'objective_verify');

    final outcome = await stage.run(context());

    expect(
      container.read(settingsNotifierProvider).baseUrl,
      'http://192.168.100.242:1234/v1',
    );
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no longer eligible'));
    expect(dataSource.requestCount, 0);
    expect(
      container.read(ll37ObjectiveVerdictHistoryNotifierProvider),
      isEmpty,
    );
  });

  test(
    'objective_verify caps two-route disagreement across idle runs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var requests = 0;
      const candidate = Ll37ObjectiveCandidate(
        id: 'two-route-disagreement',
        sourceSurface: Ll37ObjectiveSourceSurface.routine,
        attended: false,
        ll34OutcomeSettled: false,
        objective: 'Set enabled to true.',
        acceptanceCriteria: ['settings.json contains enabled true.'],
        changedFiles: [
          Ll37ObjectiveChangedFile(
            path: 'settings.json',
            content: '{"enabled":true}',
          ),
        ],
      );
      final responses = [
        {
          'verdict': 'not_refuted',
          'confidence': 1,
          'blocking': 'none',
          'findings': <Object?>[],
        },
        {
          'verdict': 'refuted',
          'confidence': 1,
          'blocking': 'contradiction',
          'findings': [
            {
              'kind': 'unmet_criterion',
              'location': 'settings.json',
              'detail': 'enabled remains false',
            },
          ],
        },
      ];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          maintenanceLl37EligibleVerifierProfilesProvider.overrideWithValue(
            Ll37VerifierFidelityRegistry.acceptedProfiles,
          ),
          maintenanceLl37ObjectiveCandidateSourceProvider.overrideWithValue(
            () async => const [candidate],
          ),
          maintenanceLl37ObjectiveVerificationPanelFactoryProvider
              .overrideWithValue(
                (_) => Ll37ObjectiveVerificationPanel(
                  complete: (_, _) async {
                    final response = responses[requests];
                    requests += 1;
                    return jsonEncode(response);
                  },
                ),
              ),
        ],
      );
      addTearDown(container.dispose);
      final stage = container
          .read(maintenanceStagesProvider)
          .firstWhere((item) => item.name == 'objective_verify');

      final first = await stage.run(context());
      final second = await stage.run(context());
      final third = await stage.run(context());

      expect(first.detail, contains('objective vote 1/2'));
      expect(second.detail, contains('objective vote 2/2'));
      expect(second.detail, contains('capped/unverifiable'));
      expect(third.status, MaintenanceStageStatus.skipped);
      expect(third.detail, contains('require another vote'));
      expect(requests, 2);
      expect(
        container.read(ll37ObjectiveVerdictHistoryNotifierProvider),
        hasLength(2),
      );
    },
  );

  test('objective_verify does not persist a cancelled report', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const candidate = Ll37ObjectiveCandidate(
      id: 'cancelled-candidate',
      sourceSurface: Ll37ObjectiveSourceSurface.routine,
      attended: false,
      ll34OutcomeSettled: false,
      objective: 'Set enabled to true.',
      acceptanceCriteria: ['settings.json contains enabled true.'],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        maintenanceLl37EligibleVerifierProfilesProvider.overrideWithValue(
          Ll37VerifierFidelityRegistry.acceptedProfiles,
        ),
        maintenanceLl37ObjectiveCandidateSourceProvider.overrideWithValue(
          () async => const [candidate],
        ),
      ],
    );
    addTearDown(container.dispose);
    final handle = IdleMaintenanceRunHandle()..cancel();
    final stage = container
        .read(maintenanceStagesProvider)
        .firstWhere((item) => item.name == 'objective_verify');

    final outcome = await stage.run(
      MaintenanceStageContext(handle: handle, shared: <String, Object?>{}),
    );

    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(
      container.read(ll37ObjectiveVerdictHistoryNotifierProvider),
      isEmpty,
    );
  });

  test('objective_verify propagates verdict persistence failure', () async {
    const candidate = Ll37ObjectiveCandidate(
      id: 'persist-failure',
      sourceSurface: Ll37ObjectiveSourceSurface.routine,
      attended: false,
      ll34OutcomeSettled: false,
      objective: 'Set enabled to true.',
      acceptanceCriteria: ['settings.json contains enabled true.'],
    );
    final container = ProviderContainer(
      overrides: [
        maintenanceLl37EligibleVerifierProfilesProvider.overrideWithValue(
          Ll37VerifierFidelityRegistry.acceptedProfiles,
        ),
        maintenanceLl37ObjectiveCandidateSourceProvider.overrideWithValue(
          () async => const [candidate],
        ),
        maintenanceLl37ObjectiveVerificationPanelFactoryProvider
            .overrideWithValue(
              (_) => Ll37ObjectiveVerificationPanel(
                complete: (_, _) async => jsonEncode({
                  'verdict': 'not_refuted',
                  'confidence': 1,
                  'blocking': 'none',
                  'findings': <Object?>[],
                }),
              ),
            ),
        ll37ObjectiveVerdictHistoryNotifierProvider.overrideWith(
          _FailingVerdictHistoryNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    final stage = container
        .read(maintenanceStagesProvider)
        .firstWhere((item) => item.name == 'objective_verify');

    await expectLater(stage.run(context()), throwsStateError);
  });

  test('interactive chat code cannot import LL37 idle verification', () {
    const forbiddenSymbols = [
      'Ll37ObjectiveVerificationPanel',
      'Ll37ObjectiveContinuationPolicy',
    ];
    final references = Directory('lib/features/chat')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => forbiddenSymbols.any(file.readAsStringSync().contains))
        .toList(growable: false);

    expect(references, isEmpty);
  });

  test('precompute skips when there is no active coding project', () async {
    final container = ProviderContainer(
      overrides: [
        codingProjectsNotifierProvider.overrideWith(
          () => _FakeCodingProjectsNotifier(
            const CodingProjectsState(projects: [], selectedProjectId: null),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final precompute = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'precompute');
    final outcome = await precompute.run(context());

    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no active coding project'));
  });

  test('precompute and warm_cache reuse the production LSP repo map', () async {
    final projectDirectory = Directory.systemTemp.createTempSync(
      'caverno_ll22_lsp_',
    );
    addTearDown(() => projectDirectory.deleteSync(recursive: true));
    final source = File('${projectDirectory.path}/sample.dart')
      ..writeAsStringSync('void main() {}\n');
    final now = DateTime.utc(2026, 8, 14);
    final project = CodingProject(
      id: 'project-1',
      name: 'LL22 fixture',
      rootPath: projectDirectory.path,
      createdAt: now,
      updatedAt: now,
    );
    final repoMapCache = RepoMapPrecomputeCache();
    final lspCache = RepoMapLspSymbolCache()
      ..updateFromLsp(
        projectRoot: projectDirectory.path,
        changedPaths: [source.path],
        symbols: [
          LspDocumentSymbol(
            uri: source.uri.toString(),
            name: 'main',
            kind: 12,
            kindLabel: 'Function',
            startLine: 0,
            startCharacter: 5,
          ),
        ],
      );
    final definitions = _toolDefinitions(30);
    final dataSource = _RecordingVerifierDataSource();
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          () => _FixedSettingsNotifier(AppSettings.defaults()),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FakeCodingProjectsNotifier(
            CodingProjectsState(
              projects: [project],
              selectedProjectId: project.id,
            ),
          ),
        ),
        repoMapPrecomputeCacheProvider.overrideWithValue(repoMapCache),
        repoMapLspSymbolCacheProvider.overrideWithValue(lspCache),
        mcpToolServiceProvider.overrideWithValue(
          _FixedMcpToolService(definitions),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      ],
    );
    addTearDown(container.dispose);
    final stages = container.read(maintenanceStagesProvider);

    final precompute = await stages
        .firstWhere((stage) => stage.name == 'precompute')
        .run(context());
    final warm = await stages
        .firstWhere((stage) => stage.name == 'warm_cache')
        .run(context());

    expect(precompute.status, MaintenanceStageStatus.completed);
    expect(precompute.detail, contains('precomputed repo map'));
    expect(warm.status, MaintenanceStageStatus.completed);
    expect(dataSource.messages!.first.content, contains('LSP symbols:'));
    expect(
      dataSource.messages!.first.content,
      contains('sample.dart: function main'),
    );
    expect(
      repoMapCache.precompute(
        rootPath: projectDirectory.path,
        lspSymbolEntries: lspCache.entriesForRoot(projectDirectory.path),
      ),
      RepoMapPrecomputeResult.alreadyWarm,
    );
  });

  test('warm_cache uses the production initial selection by default', () async {
    final definitions = _toolDefinitions(30);
    final expected = ToolDefinitionSearchService.buildInitialSelection(
      definitions,
    ).toolDefinitions;
    final dataSource = _RecordingVerifierDataSource();
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          () => _FixedSettingsNotifier(AppSettings.defaults()),
        ),
        mcpToolServiceProvider.overrideWithValue(
          _FixedMcpToolService(definitions),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        codingProjectsNotifierProvider.overrideWith(
          () => _FakeCodingProjectsNotifier(
            const CodingProjectsState(projects: [], selectedProjectId: null),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(maintenanceStagesProvider)
        .firstWhere((stage) => stage.name == 'warm_cache')
        .run(context());

    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(dataSource.requestCount, 1);
    expect(dataSource.tools, expected);
    expect(dataSource.tools!.length, lessThan(definitions.length));
    expect(
      dataSource.messages!.first.content,
      contains(ToolDefinitionSearchService.toolName),
    );
    expect(dataSource.messages!.first.content, isNot(contains('tool_29')));
  });

  test('warm_cache preserves the full catalog in prefix-stable mode', () async {
    final definitions = _toolDefinitions(30);
    final dataSource = _RecordingVerifierDataSource();
    final settings = AppSettings.defaults().copyWith(
      enablePrefixStableToolLoop: true,
    );
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          () => _FixedSettingsNotifier(settings),
        ),
        mcpToolServiceProvider.overrideWithValue(
          _FixedMcpToolService(definitions),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        codingProjectsNotifierProvider.overrideWith(
          () => _FakeCodingProjectsNotifier(
            const CodingProjectsState(projects: [], selectedProjectId: null),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(maintenanceStagesProvider)
        .firstWhere((stage) => stage.name == 'warm_cache')
        .run(context());

    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(dataSource.tools, definitions);
    expect(outcome.detail, contains('30 tool(s)'));
  });

  test('warm_cache skips an empty tool catalog', () async {
    final dataSource = _RecordingVerifierDataSource();
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          () => _FixedSettingsNotifier(AppSettings.defaults()),
        ),
        mcpToolServiceProvider.overrideWithValue(
          _FixedMcpToolService(const []),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      ],
    );
    addTearDown(container.dispose);

    final outcome = await container
        .read(maintenanceStagesProvider)
        .firstWhere((stage) => stage.name == 'warm_cache')
        .run(context());

    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('tool catalog is empty'));
    expect(dataSource.requestCount, 0);
  });

  test('mine skips when there are no failure traces', () async {
    final container = ProviderContainer(
      overrides: [
        maintenanceFailureTraceSourceProvider.overrideWithValue(
          () async => const [],
        ),
      ],
    );
    addTearDown(container.dispose);
    final mine = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'mine');
    final outcome = await mine.run(context());
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no failure traces'));
  });

  test('propose skips when no weakness was mined', () async {
    final propose = stages().firstWhere((s) => s.name == 'propose');
    final outcome = await propose.run(context());
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no mined weakness'));
  });

  test('mine reports the clustered weaknesses when traces exist', () async {
    const signature = FailureSignature(
      terminalCause: 'edit_apply_failed',
      causalStatus: 'tests_failed',
      mechanism: 'stale_old_text',
    );
    final container = ProviderContainer(
      overrides: [
        maintenanceFailureTraceSourceProvider.overrideWithValue(
          () async => const [
            FailureTrace(caseId: 'a', signature: signature),
            FailureTrace(caseId: 'b', signature: signature),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    final mine = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'mine');
    final outcome = await mine.run(context());

    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(outcome.detail, contains('mined 1 cluster(s)'));
    expect(outcome.detail, contains('x2'));
  });

  test('adopt skips when no candidate has been proposed', () async {
    final adopt = stages().firstWhere((s) => s.name == 'adopt');
    final outcome = await adopt.run(context());
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no candidate proposed'));
  });

  test('adopt skips when eval cases are not available', () async {
    // The bare container has no eval cases loaded, so adopt falls through to
    // the eval-gated path and skips because there is nothing to validate against.
    final adopt = stages().firstWhere((s) => s.name == 'adopt');
    final outcome = await adopt.run(
      context({
        maintenanceProposedCandidateKey: const HarnessConfigProposal(
          mechanism: 'stale_old_text',
          surface: 'failureRecoveryInstruction',
          rationale: 'r',
          proposedConfig: ModelHarnessConfig(id: 'p', model: 'm'),
        ),
      }),
    );
    expect(outcome.status, MaintenanceStageStatus.skipped);
    expect(outcome.detail, contains('no recorded eval cases'));
  });

  test(
    'adopt surfaces manual-review when proposal touches a high-risk surface',
    () async {
      // A high-risk surface is blocked even when eval cases would be available.
      final adopt = stages().firstWhere((s) => s.name == 'adopt');
      final outcome = await adopt.run(
        context({
          maintenanceProposedCandidateKey: const HarnessConfigProposal(
            mechanism: 'some_mechanism',
            surface: 'approvalMode',
            rationale: 'r',
            proposedConfig: ModelHarnessConfig(id: 'p', model: 'm'),
          ),
        }),
      );
      expect(outcome.status, MaintenanceStageStatus.completed);
      expect(outcome.detail, contains('manual review required'));
      expect(outcome.detail, contains('approvalMode'));
    },
  );

  test('adopt auto-adopts when eval passes on both splits', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const proposal = HarnessConfigProposal(
      mechanism: 'stale_old_text',
      surface: 'failureRecoveryInstruction',
      rationale: 'r',
      proposedConfig: ModelHarnessConfig(
        id: 'p',
        model: 'm',
        failureRecoveryInstruction: 're-read before retry',
      ),
    );
    final evalCase = PersonalEvalCase(
      caseId: 'c1',
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Inject a runner factory that always passes so no live providers needed.
        maintenanceEvalRunnerFactoryProvider.overrideWithValue(
          (_) => _PassingRunner(),
        ),
        personalEvalCasesNotifierProvider.overrideWith(
          () => _FakeCasesNotifier([evalCase]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Wait for the cases notifier to finish loading.
    await container.read(personalEvalCasesNotifierProvider.future);

    final adopt = container
        .read(maintenanceStagesProvider)
        .firstWhere((s) => s.name == 'adopt');
    final outcome = await adopt.run(
      context({maintenanceProposedCandidateKey: proposal}),
    );
    // Eval passes → adopted, not just recommended.
    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(outcome.detail, contains('adopted'));
    expect(outcome.detail, contains('failureRecoveryInstruction'));
  });
}

WorktreeAgentTask _eligibleWorktreeAgentTask() {
  const content = "String greeting() => 'hello';\n";
  final bytes = utf8.encode(content);
  final now = DateTime.utc(2026, 8, 13);
  return WorktreeAgentTask(
    id: 'task-1',
    status: WorktreeAgentTaskStatus.completed,
    title: 'Update greeting',
    prompt: 'Update the greeting implementation.',
    branchName: 'feature/ll13-task-1',
    worktreePath: '/tmp/caverno-worktrees/task-1',
    verificationCommand: 'dart test',
    objectiveAcceptanceCriteria: const ['lib/greeting.dart returns hello.'],
    createdAt: now.subtract(const Duration(minutes: 1)),
    updatedAt: now,
    finishedAt: now,
    resultSummary: 'Updated the greeting implementation.',
    verifiedGreen: true,
    verificationSummary: 'Verification passed: dart test (exit code 0).',
    changedFiles: [
      WorktreeAgentChangedFileEvidence(
        path: 'lib/greeting.dart',
        content: content,
        contentHash: sha256.convert(bytes).toString(),
        byteSize: bytes.length,
      ),
    ],
  );
}

List<Map<String, dynamic>> _toolDefinitions(int count) => [
  for (var index = 0; index < count; index += 1)
    {
      'type': 'function',
      'function': {
        'name': 'tool_$index',
        'description': 'Synthetic maintenance tool $index.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
];
