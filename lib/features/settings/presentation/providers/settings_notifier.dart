import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../data/external_settings_service.dart';
import '../../data/settings_file_service.dart';
import '../../data/settings_qr_service.dart';
import '../../data/settings_repository.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/services/llm_sampler_runtime_feedback_service.dart';
import '../../domain/services/local_command_permission_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main');
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(sharedPreferencesProvider));
});

final externalSettingsServiceProvider = Provider<ExternalSettingsService>((
  ref,
) {
  return ExternalSettingsService();
});

final settingsNotifierProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  late final SettingsRepository _repository;
  late final SettingsFileService _fileService;
  late final SettingsQrService _qrService;
  late final ExternalSettingsService _externalSettingsService;
  bool _isSyncingExternalSettings = false;

  @override
  AppSettings build() {
    _repository = ref.read(settingsRepositoryProvider);
    _fileService = ref.read(settingsFileServiceProvider);
    _qrService = ref.read(settingsQrServiceProvider);
    _externalSettingsService = ref.read(externalSettingsServiceProvider);
    final settings = _repository.load();
    if (settings.externalSettingsSyncEnabled) {
      unawaited(Future<void>.microtask(syncExternalSettings));
    }
    return settings;
  }

  Future<void> updateBaseUrl(String baseUrl) async {
    state = state.copyWith(baseUrl: baseUrl);
    await _repository.save(state);
  }

  Future<void> updateModel(String model) async {
    state = state.copyWith(model: model);
    await _repository.save(state);
  }

  Future<void> updateApiKey(String apiKey) async {
    state = state.copyWith(apiKey: apiKey);
    await _repository.save(state);
  }

  Future<void> applyNvidiaNimCloudPreset() async {
    final currentApiKey = state.apiKey.trim();
    state = state.copyWith(
      llmProvider: LlmProvider.openAiCompatible,
      baseUrl: ApiConstants.nvidiaNimBaseUrl,
      model: ApiConstants.nvidiaNimDefaultModel,
      apiKey: currentApiKey == ApiConstants.defaultApiKey ? '' : state.apiKey,
      assistantMode: _assistantModeForProvider(
        provider: LlmProvider.openAiCompatible,
        assistantMode: state.assistantMode,
      ),
    );
    await _repository.save(state);
  }

  Future<void> updateMemoryExtractionModel(String model) async {
    state = state.copyWith(memoryExtractionModel: model.trim());
    await _repository.save(state);
  }

  Future<void> updateSubagentModel(String model) async {
    state = state.copyWith(subagentModel: model.trim());
    await _repository.save(state);
  }

  Future<void> updateGoalSuggestionModel(String model) async {
    state = state.copyWith(goalSuggestionModel: model.trim());
    await _repository.save(state);
  }

  Future<void> updateApprovalAutoReviewModel(String model) async {
    state = state.copyWith(approvalAutoReviewModel: model.trim());
    await _repository.save(state);
  }

  /// LL8: assign a role's secondary calls to a registered mesh endpoint. An
  /// empty id routes the role to the primary endpoint.
  Future<void> updateMemoryExtractionEndpointId(String endpointId) async {
    state = state.copyWith(memoryExtractionEndpointId: endpointId.trim());
    await _repository.save(state);
  }

  Future<void> updateSubagentEndpointId(String endpointId) async {
    state = state.copyWith(subagentEndpointId: endpointId.trim());
    await _repository.save(state);
  }

  Future<void> updateGoalSuggestionEndpointId(String endpointId) async {
    state = state.copyWith(goalSuggestionEndpointId: endpointId.trim());
    await _repository.save(state);
  }

  Future<void> updateApprovalAutoReviewEndpointId(String endpointId) async {
    state = state.copyWith(approvalAutoReviewEndpointId: endpointId.trim());
    await _repository.save(state);
  }

  Future<void> upsertModelCapabilityProfile(
    ModelCapabilityProfile profile, {
    String source = 'probe',
  }) async {
    // LL16: reset runtime step-downs when a fresh probe or calibration result
    // arrives — the model has been re-measured so stale counters are invalid.
    final effective = (source == 'idle_re_probe' || source == 'calibrate')
        ? const LlmSamplerRuntimeFeedbackService().recoverAfterReprobe(
            profile: profile,
            probeSource: source,
          )
        : profile;
    final normalized = effective.normalizedForPersistence();
    if (normalized.normalizedModel.isEmpty) {
      throw ArgumentError('Model capability profile model is required');
    }

    final profiles = List<ModelCapabilityProfile>.from(
      state.modelCapabilityProfiles,
    );
    final index = profiles.indexWhere((item) => item.id == normalized.id);
    if (index == -1) {
      profiles.add(normalized);
    } else {
      profiles[index] = normalized;
    }

    // LL21: append a revision snapshot for history and model-swap detection.
    final revisions = _buildUpdatedRevisions(
      normalized,
      source: source,
      existing: state.modelCapabilityProfileRevisions,
    );

    state = state.copyWith(
      modelCapabilityProfiles: profiles,
      modelCapabilityProfileRevisions: revisions,
    );
    await _repository.save(state);
  }

  static List<ModelCapabilityProfileRevision> _buildUpdatedRevisions(
    ModelCapabilityProfile profile, {
    required String source,
    required List<ModelCapabilityProfileRevision> existing,
  }) {
    // Find the most recent previous revision for this profile id.
    ModelCapabilityProfileRevision? prev;
    for (var i = existing.length - 1; i >= 0; i--) {
      if (existing[i].profileId == profile.computedId) {
        prev = existing[i];
        break;
      }
    }

    final capabilityChangeDetected =
        prev != null && _hasCapabilityChanged(profile, prev);

    final newRevision = ModelCapabilityProfileRevision.fromProfile(
      profile,
      source: source,
      capabilityChangeDetected: capabilityChangeDetected,
    );

    // Partition: revisions for this profile vs all others.
    final thisProfile = existing
        .where((r) => r.profileId == profile.computedId)
        .toList(growable: true);
    final others = existing
        .where((r) => r.profileId != profile.computedId)
        .toList(growable: false);

    thisProfile.add(newRevision);
    if (thisProfile.length > ModelCapabilityProfileRevision.maxPerProfile) {
      thisProfile.removeRange(
        0,
        thisProfile.length - ModelCapabilityProfileRevision.maxPerProfile,
      );
    }

    return [...others, ...thisProfile];
  }

  static bool _hasCapabilityChanged(
    ModelCapabilityProfile profile,
    ModelCapabilityProfileRevision prev,
  ) {
    if (profile.toolCallStyle != prev.toolCallStyle) return true;
    if (profile.structuredOutputSupport != prev.structuredOutputSupport) {
      return true;
    }
    if (profile.editFormatPreference != prev.editFormatPreference) return true;
    // Flag context-token drift beyond 20% in either direction.
    if (prev.usableContextTokens > 0 && profile.usableContextTokens > 0) {
      final ratio = profile.usableContextTokens / prev.usableContextTokens;
      if (ratio < 0.8 || ratio > 1.25) return true;
    }
    return false;
  }

  Future<void> removeModelCapabilityProfile(String profileId) async {
    final normalizedId = profileId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    final profiles = state.modelCapabilityProfiles
        .where((profile) => profile.id != normalizedId)
        .toList(growable: false);
    state = state.copyWith(modelCapabilityProfiles: profiles);
    await _repository.save(state);
  }

  /// LL23: store the per-model harness config. An override-free config is
  /// dropped instead of persisted, so it never shadows a future config or
  /// changes behaviour.
  Future<void> upsertModelHarnessConfig(ModelHarnessConfig config) async {
    final normalized = config.normalizedForPersistence();
    if (normalized.normalizedModel.isEmpty) {
      throw ArgumentError('Model harness config model is required');
    }

    final configs = List<ModelHarnessConfig>.from(state.modelHarnessConfigs);
    final index = configs.indexWhere((item) => item.id == normalized.id);
    if (normalized.isEmpty) {
      if (index != -1) {
        configs.removeAt(index);
        state = state.copyWith(modelHarnessConfigs: configs);
        await _repository.save(state);
      }
      return;
    }
    if (index == -1) {
      configs.add(normalized);
    } else {
      configs[index] = normalized;
    }
    state = state.copyWith(modelHarnessConfigs: configs);
    await _repository.save(state);
  }

  Future<void> removeModelHarnessConfig(String configId) async {
    final normalizedId = configId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    final configs = state.modelHarnessConfigs
        .where((config) => config.id != normalizedId)
        .toList(growable: false);
    state = state.copyWith(modelHarnessConfigs: configs);
    await _repository.save(state);
  }

  /// LL8: register or update a LAN mesh endpoint, keyed by its normalized base
  /// URL so re-registering the same endpoint updates in place. Registration is
  /// always explicit (called from user-confirmed UI), never from discovery.
  Future<void> upsertNamedEndpoint(NamedEndpoint endpoint) async {
    final normalized = endpoint
        .copyWith(createdAt: endpoint.createdAt ?? DateTime.now())
        .normalizedForPersistence();
    if (!normalized.isValid) {
      throw ArgumentError('NamedEndpoint base URL is required');
    }
    final endpoints = List<NamedEndpoint>.from(state.namedEndpoints);
    final index = endpoints.indexWhere((item) => item.id == normalized.id);
    if (index == -1) {
      endpoints.add(normalized);
    } else {
      // Preserve the original registration time on update.
      endpoints[index] = normalized.copyWith(
        createdAt: endpoints[index].createdAt ?? normalized.createdAt,
      );
    }
    state = state.copyWith(namedEndpoints: endpoints);
    await _repository.save(state);
  }

  /// LL8: remove a registered LAN mesh endpoint by id.
  Future<void> removeNamedEndpoint(String endpointId) async {
    final normalizedId = endpointId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    final endpoints = state.namedEndpoints
        .where((endpoint) => endpoint.id != normalizedId)
        .toList(growable: false);
    state = state.copyWith(namedEndpoints: endpoints);
    await _repository.save(state);
  }

  Future<void> updateTemperature(double temperature) async {
    state = state.copyWith(temperature: temperature);
    await _repository.save(state);
  }

  Future<void> updateMaxTokens(int maxTokens) async {
    state = state.copyWith(maxTokens: maxTokens);
    await _repository.save(state);
  }

  /// Updates the LL18 idle/overnight maintenance gating settings. Only the
  /// provided fields change; the rest are preserved.
  Future<void> updateIdleMaintenance({
    bool? enabled,
    int? windowStartMinutes,
    int? windowEndMinutes,
    int? minIdleMinutes,
    bool? requireAcPower,
  }) async {
    state = state.copyWith(
      idleMaintenanceEnabled: enabled ?? state.idleMaintenanceEnabled,
      idleMaintenanceWindowStartMinutes:
          windowStartMinutes ?? state.idleMaintenanceWindowStartMinutes,
      idleMaintenanceWindowEndMinutes:
          windowEndMinutes ?? state.idleMaintenanceWindowEndMinutes,
      idleMaintenanceMinIdleMinutes:
          minIdleMinutes ?? state.idleMaintenanceMinIdleMinutes,
      idleMaintenanceRequireAcPower:
          requireAcPower ?? state.idleMaintenanceRequireAcPower,
    );
    await _repository.save(state);
  }

  Future<void> updateReasoningEffort(
    ReasoningEffortPreference reasoningEffort,
  ) async {
    state = state.copyWith(reasoningEffort: reasoningEffort);
    await _repository.save(state);
  }

  Future<void> updateLlmProvider(LlmProvider llmProvider) async {
    state = state.copyWith(
      llmProvider: llmProvider,
      assistantMode: _assistantModeForProvider(
        provider: llmProvider,
        assistantMode: state.assistantMode,
      ),
    );
    await _repository.save(state);
  }

  Future<void> updateGoogleChatWebhookUrl(String webhookUrl) async {
    state = state.copyWith(googleChatWebhookUrl: webhookUrl.trim());
    await _repository.save(state);
  }

  Future<void> updateMcpUrl(String mcpUrl) async {
    await updateMcpUrls(mcpUrl.isEmpty ? const [] : [mcpUrl]);
  }

  Future<void> updateMcpUrls(List<String> mcpUrls) async {
    await updateMcpServers(AppSettings.buildMcpServersFromUrls(mcpUrls));
  }

  Future<void> updateMcpServers(List<McpServerConfig> mcpServers) async {
    final normalizedServers = <McpServerConfig>[
      for (var index = 0; index < mcpServers.length; index++)
        _normalizeMcpServerForPersistence(
          previous: index < state.configuredMcpServers.length
              ? state.configuredMcpServers[index]
              : null,
          next: mcpServers[index],
        ),
    ];

    final httpServers = normalizedServers.where(
      (s) => s.type == McpServerType.http,
    );
    final activeUrls = AppSettings.activeMcpUrlsFromServers(httpServers);
    state = state.copyWith(
      mcpUrl: activeUrls.isEmpty ? '' : activeUrls.first,
      mcpUrls: activeUrls,
      mcpServers: normalizedServers,
    );
    await _repository.save(state);
  }

  Future<void> addMcpServer() async {
    await updateMcpServers([
      ...state.configuredMcpServers,
      const McpServerConfig(trustState: McpServerTrustState.pending),
    ]);
  }

  Future<void> addMcpStdioServer() async {
    await updateMcpServers([
      ...state.configuredMcpServers,
      const McpServerConfig(
        type: McpServerType.stdio,
        trustState: McpServerTrustState.pending,
      ),
    ]);
  }

  Future<void> updateMcpServerUrl(int index, String url) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    servers[index] = servers[index].copyWith(
      url: url,
      trustState: McpServerTrustState.pending,
      trustedAt: null,
    );
    await updateMcpServers(servers);
  }

  Future<void> updateMcpServerCommand(int index, String command) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    servers[index] = servers[index].copyWith(
      command: command,
      trustState: McpServerTrustState.pending,
      trustedAt: null,
    );
    await updateMcpServers(servers);
  }

  Future<void> updateMcpServerArgs(int index, String argsString) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    final args = argsString.trim().isEmpty
        ? <String>[]
        : argsString.split(RegExp(r'\s+')).toList();
    servers[index] = servers[index].copyWith(
      args: args,
      trustState: McpServerTrustState.pending,
      trustedAt: null,
    );
    await updateMcpServers(servers);
  }

  Future<void> updateMcpServerEnabled(int index, bool enabled) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    servers[index] = servers[index].copyWith(enabled: enabled);
    await updateMcpServers(servers);
  }

  Future<void> updateMcpServerTrustState(
    int index,
    McpServerTrustState trustState,
  ) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    servers[index] = servers[index].copyWith(
      trustState: trustState,
      trustedAt: trustState == McpServerTrustState.trusted
          ? DateTime.now()
          : null,
    );
    await updateMcpServers(servers);
  }

  Future<void> removeMcpServer(int index) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    servers.removeAt(index);
    await updateMcpServers(servers);
  }

  Future<void> toggleBuiltInTool(String toolName, bool enabled) async {
    final current = Set<String>.from(state.disabledBuiltInTools);
    enabled ? current.remove(toolName) : current.add(toolName);
    state = state.copyWith(disabledBuiltInTools: current.toList());
    await _repository.save(state);
  }

  Future<void> setBuiltInToolsCategoryDisabled(
    Set<String> toolNames,
    bool disabled,
  ) async {
    final current = Set<String>.from(state.disabledBuiltInTools);
    disabled ? current.addAll(toolNames) : current.removeAll(toolNames);
    state = state.copyWith(disabledBuiltInTools: current.toList());
    await _repository.save(state);
  }

  Future<void> upsertLocalCommandPermissionRule(
    LocalCommandPermissionRule rule,
  ) async {
    final validationError = LocalCommandPermissionService.validateRule(rule);
    if (validationError != null) {
      throw ArgumentError(validationError);
    }

    final normalizedRule = rule.copyWith(
      pattern: LocalCommandPermissionService.normalizePattern(rule.pattern),
      workingDirectory: LocalCommandPermissionService.normalizePattern(
        rule.workingDirectory,
      ),
      createdAt: rule.createdAt ?? DateTime.now(),
    );
    final rules = List<LocalCommandPermissionRule>.from(
      state.localCommandPermissionRules,
    );
    final index = rules.indexWhere((item) => item.id == normalizedRule.id);
    if (index == -1) {
      rules.add(normalizedRule);
    } else {
      rules[index] = normalizedRule;
    }
    state = state.copyWith(localCommandPermissionRules: rules);
    await _repository.save(state);
  }

  Future<void> toggleLocalCommandPermissionRule(
    String ruleId,
    bool enabled,
  ) async {
    final rules = [
      for (final rule in state.localCommandPermissionRules)
        rule.id == ruleId ? rule.copyWith(enabled: enabled) : rule,
    ];
    state = state.copyWith(localCommandPermissionRules: rules);
    await _repository.save(state);
  }

  Future<void> removeLocalCommandPermissionRule(String ruleId) async {
    final rules = state.localCommandPermissionRules
        .where((rule) => rule.id != ruleId)
        .toList(growable: false);
    state = state.copyWith(localCommandPermissionRules: rules);
    await _repository.save(state);
  }

  Future<void> upsertRoutineComputerUseActionAllowlistEntry(
    RoutineComputerUseActionAllowlistEntry entry,
  ) async {
    final entries = List<RoutineComputerUseActionAllowlistEntry>.from(
      state.routineComputerUseActionAllowlist,
    );
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    state = state.copyWith(routineComputerUseActionAllowlist: entries);
    await _repository.save(state);
  }

  Future<void> toggleRoutineComputerUseActionAllowlistEntry(
    String entryId,
    bool enabled,
  ) async {
    final entries = [
      for (final entry in state.routineComputerUseActionAllowlist)
        entry.id == entryId ? entry.copyWith(enabled: enabled) : entry,
    ];
    state = state.copyWith(routineComputerUseActionAllowlist: entries);
    await _repository.save(state);
  }

  Future<void> removeRoutineComputerUseActionAllowlistEntry(
    String entryId,
  ) async {
    final entries = state.routineComputerUseActionAllowlist
        .where((entry) => entry.id != entryId)
        .toList(growable: false);
    state = state.copyWith(routineComputerUseActionAllowlist: entries);
    await _repository.save(state);
  }

  Future<void> updateMcpEnabled(bool mcpEnabled) async {
    state = state.copyWith(mcpEnabled: mcpEnabled);
    await _repository.save(state);
  }

  Future<void> updateExternalSettingsSyncEnabled(bool enabled) async {
    state = state.copyWith(externalSettingsSyncEnabled: enabled);
    await _repository.save(state);
    if (enabled) {
      await syncExternalSettings();
    }
  }

  Future<void> updateExternalToolHooksEnabled(bool enabled) async {
    state = state.copyWith(externalToolHooksEnabled: enabled);
    await _repository.save(state);
  }

  Future<void> updateExternalSettingsPath(String path) async {
    state = state.copyWith(externalSettingsPath: path.trim());
    await _repository.save(state);
    if (state.externalSettingsSyncEnabled) {
      await syncExternalSettings();
    }
  }

  Future<void> applyAgentKbIntegrationPreset() async {
    state = _externalSettingsService.applyAgentKbPreset(state);
    await _repository.save(state);
    await syncExternalSettings();
  }

  Future<bool> syncExternalSettings() async {
    if (_isSyncingExternalSettings) {
      return false;
    }
    _isSyncingExternalSettings = true;
    try {
      final synced = await _externalSettingsService.sync(state);
      if (synced == state) {
        return false;
      }
      state = synced;
      await _repository.save(state);
      return true;
    } finally {
      _isSyncingExternalSettings = false;
    }
  }

  // Voice settings
  Future<void> updateTtsEnabled(bool ttsEnabled) async {
    state = state.copyWith(ttsEnabled: ttsEnabled);
    await _repository.save(state);
  }

  Future<void> updateAutoReadEnabled(bool autoReadEnabled) async {
    state = state.copyWith(autoReadEnabled: autoReadEnabled);
    await _repository.save(state);
  }

  Future<void> updateSpeechRate(double speechRate) async {
    state = state.copyWith(speechRate: speechRate);
    await _repository.save(state);
  }

  // Voice mode settings
  Future<void> updateVoiceModeAutoStop(bool voiceModeAutoStop) async {
    state = state.copyWith(voiceModeAutoStop: voiceModeAutoStop);
    await _repository.save(state);
  }

  Future<void> updateWhisperUrl(String whisperUrl) async {
    state = state.copyWith(whisperUrl: whisperUrl);
    await _repository.save(state);
  }

  Future<void> updateVoicevoxUrl(String voicevoxUrl) async {
    state = state.copyWith(voicevoxUrl: voicevoxUrl);
    await _repository.save(state);
  }

  Future<void> updateVoicevoxSpeakerId(int voicevoxSpeakerId) async {
    state = state.copyWith(voicevoxSpeakerId: voicevoxSpeakerId);
    await _repository.save(state);
  }

  Future<void> updateLanguage(String language) async {
    state = state.copyWith(language: language);
    await _repository.save(state);
  }

  Future<void> updateAssistantMode(AssistantMode assistantMode) async {
    state = state.copyWith(
      assistantMode: _assistantModeForProvider(
        provider: state.llmProvider,
        assistantMode: assistantMode,
      ),
    );
    await _repository.save(state);
  }

  AssistantMode _assistantModeForProvider({
    required LlmProvider provider,
    required AssistantMode assistantMode,
  }) {
    if (provider == LlmProvider.appleFoundationModels &&
        assistantMode == AssistantMode.plan) {
      return AssistantMode.general;
    }
    return assistantMode;
  }

  Future<void> updateEnableAgentsMd(bool value) async {
    state = state.copyWith(enableAgentsMd: value);
    await _repository.save(state);
  }

  Future<void> updateEnablePrefixStableToolLoop(bool value) async {
    state = state.copyWith(enablePrefixStableToolLoop: value);
    await _repository.save(state);
  }

  /// LL5: toggle local semantic search over conversation history.
  Future<void> updateEnableSemanticSearch(bool value) async {
    state = state.copyWith(enableSemanticSearch: value);
    await _repository.save(state);
  }

  /// LL5: set the embeddings model used to index and search history.
  Future<void> updateEmbeddingsModel(String value) async {
    state = state.copyWith(embeddingsModel: value.trim());
    await _repository.save(state);
  }

  Future<void> updateBrowserToolsEnabled(bool value) async {
    state = state.copyWith(browserToolsEnabled: value);
    await _repository.save(state);
  }

  Future<void> updateCodingApprovalMode(
    ToolApprovalMode codingApprovalMode,
  ) async {
    final confirms = codingApprovalMode != ToolApprovalMode.fullAccess;
    state = state.copyWith(
      codingApprovalMode: codingApprovalMode,
      confirmFileMutations: confirms,
      confirmLocalCommands: confirms,
      confirmGitWrites: confirms,
    );
    await _repository.save(state);
  }

  Future<void> updateChatApprovalMode(ToolApprovalMode chatApprovalMode) async {
    state = state.copyWith(chatApprovalMode: chatApprovalMode);
    await _repository.save(state);
  }

  Future<void> updateConfirmFileMutations(bool value) async {
    final confirmLocalCommands = state.confirmLocalCommands;
    final confirmGitWrites = state.confirmGitWrites;
    state = state.copyWith(
      confirmFileMutations: value,
      codingApprovalMode: _legacyCodingApprovalModeFor(
        confirmFileMutations: value,
        confirmLocalCommands: confirmLocalCommands,
        confirmGitWrites: confirmGitWrites,
      ),
    );
    await _repository.save(state);
  }

  Future<void> updateConfirmLocalCommands(bool value) async {
    final confirmFileMutations = state.confirmFileMutations;
    final confirmGitWrites = state.confirmGitWrites;
    state = state.copyWith(
      confirmLocalCommands: value,
      codingApprovalMode: _legacyCodingApprovalModeFor(
        confirmFileMutations: confirmFileMutations,
        confirmLocalCommands: value,
        confirmGitWrites: confirmGitWrites,
      ),
    );
    await _repository.save(state);
  }

  Future<void> updateConfirmGitWrites(bool value) async {
    final confirmFileMutations = state.confirmFileMutations;
    final confirmLocalCommands = state.confirmLocalCommands;
    state = state.copyWith(
      confirmGitWrites: value,
      codingApprovalMode: _legacyCodingApprovalModeFor(
        confirmFileMutations: confirmFileMutations,
        confirmLocalCommands: confirmLocalCommands,
        confirmGitWrites: value,
      ),
    );
    await _repository.save(state);
  }

  Future<void> updateEnableCodingVerificationFeedback(bool value) async {
    state = state.copyWith(enableCodingVerificationFeedback: value);
    await _repository.save(state);
  }

  Future<void> updateCodingVerificationTriggerPolicy(
    CodingVerificationTriggerPolicy value,
  ) async {
    state = state.copyWith(codingVerificationTriggerPolicy: value);
    await _repository.save(state);
  }

  Future<void> updateCodingVerificationTimeoutSeconds(int value) async {
    state = state.copyWith(
      codingVerificationTimeoutSeconds: value
          .clamp(
            AppSettings.minCodingVerificationTimeoutSeconds,
            AppSettings.maxCodingVerificationTimeoutSeconds,
          )
          .toInt(),
    );
    await _repository.save(state);
  }

  Future<void> updateCodingVerificationMaxFailures(int value) async {
    state = state.copyWith(
      codingVerificationMaxFailures: value
          .clamp(
            AppSettings.minCodingVerificationMaxFailures,
            AppSettings.maxCodingVerificationMaxFailures,
          )
          .toInt(),
    );
    await _repository.save(state);
  }

  Future<void> updateShowMemoryUpdates(bool value) async {
    state = state.copyWith(showMemoryUpdates: value);
    await _repository.save(state);
  }

  Future<void> updateEnableLlmSessionLogs(bool value) async {
    state = state.copyWith(enableLlmSessionLogs: value);
    await _repository.save(state);
  }

  Future<void> updateFeedbackUploadEnabled(bool value) async {
    state = state.copyWith(feedbackUploadEnabled: value);
    await _repository.save(state);
  }

  Future<void> updateFeedbackEndpointUrl(String value) async {
    state = state.copyWith(feedbackEndpointUrl: value.trim());
    await _repository.save(state);
  }

  Future<void> updateFeedbackEndpointAuthToken(String value) async {
    state = state.copyWith(feedbackEndpointAuthToken: value.trim());
    await _repository.save(state);
  }

  Future<void> updateDemoMode(bool demoMode) async {
    state = state.copyWith(demoMode: demoMode);
    await _repository.save(state);
  }

  Future<void> completeOnboarding() async {
    if (state.onboardingCompleted) {
      return;
    }
    state = state.copyWith(onboardingCompleted: true);
    await _repository.save(state);
  }

  Future<void> updateSettings(AppSettings settings) async {
    state = settings;
    await _repository.save(state);
  }

  Future<void> resetToDefaults() async {
    state = AppSettings.defaults();
    await _repository.reset();
  }

  Future<String?> exportSettings() async {
    return _fileService.exportSettings(state);
  }

  Future<bool> importSettings() async {
    final settings = await _fileService.importSettings();
    if (settings != null) {
      state = settings;
      await _repository.save(state);
      return true;
    }
    return false;
  }

  String exportToQr() {
    return _qrService.generateQrString(state);
  }

  Future<void> importFromQr(String data) async {
    final settings = _qrService.parseQrString(data);
    state = settings;
    await _repository.save(state);
  }

  McpServerConfig _normalizeMcpServerForPersistence({
    required McpServerConfig? previous,
    required McpServerConfig next,
  }) {
    final normalized = next.type == McpServerType.http
        ? next.copyWith(url: next.normalizedUrl, sourceId: next.sourceId.trim())
        : next.copyWith(
            command: next.normalizedCommand,
            env: next.normalizedEnv,
            sourceId: next.sourceId.trim(),
          );

    if (previous == null) {
      return normalized;
    }

    if (previous.trustIdentity != normalized.trustIdentity) {
      return normalized.copyWith(
        trustState: McpServerTrustState.pending,
        trustedAt: null,
      );
    }

    return normalized;
  }

  ToolApprovalMode _legacyCodingApprovalModeFor({
    required bool confirmFileMutations,
    required bool confirmLocalCommands,
    required bool confirmGitWrites,
  }) {
    return !confirmFileMutations && !confirmLocalCommands && !confirmGitWrites
        ? ToolApprovalMode.fullAccess
        : ToolApprovalMode.defaultPermissions;
  }
}
