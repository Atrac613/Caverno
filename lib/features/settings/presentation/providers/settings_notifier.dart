import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../data/settings_file_service.dart';
import '../../data/settings_qr_service.dart';
import '../../data/settings_repository.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/services/local_command_permission_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main');
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(sharedPreferencesProvider));
});

final settingsNotifierProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  late final SettingsRepository _repository;
  late final SettingsFileService _fileService;
  late final SettingsQrService _qrService;

  @override
  AppSettings build() {
    _repository = ref.read(settingsRepositoryProvider);
    _fileService = ref.read(settingsFileServiceProvider);
    _qrService = ref.read(settingsQrServiceProvider);
    return _repository.load();
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

  Future<void> updateTemperature(double temperature) async {
    state = state.copyWith(temperature: temperature);
    await _repository.save(state);
  }

  Future<void> updateMaxTokens(int maxTokens) async {
    state = state.copyWith(maxTokens: maxTokens);
    await _repository.save(state);
  }

  Future<void> updateReasoningEffort(
    ReasoningEffortPreference reasoningEffort,
  ) async {
    state = state.copyWith(reasoningEffort: reasoningEffort);
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
    state = state.copyWith(assistantMode: assistantMode);
    await _repository.save(state);
  }

  Future<void> updateEnableAgentsMd(bool value) async {
    state = state.copyWith(enableAgentsMd: value);
    await _repository.save(state);
  }

  Future<void> updateBrowserToolsEnabled(bool value) async {
    state = state.copyWith(browserToolsEnabled: value);
    await _repository.save(state);
  }

  Future<void> updateCodingApprovalMode(
    CodingApprovalMode codingApprovalMode,
  ) async {
    final confirms = codingApprovalMode != CodingApprovalMode.fullAccess;
    state = state.copyWith(
      codingApprovalMode: codingApprovalMode,
      confirmFileMutations: confirms,
      confirmLocalCommands: confirms,
      confirmGitWrites: confirms,
    );
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
        ? next.copyWith(url: next.normalizedUrl)
        : next.copyWith(command: next.command.trim());

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

  CodingApprovalMode _legacyCodingApprovalModeFor({
    required bool confirmFileMutations,
    required bool confirmLocalCommands,
    required bool confirmGitWrites,
  }) {
    return !confirmFileMutations && !confirmLocalCommands && !confirmGitWrites
        ? CodingApprovalMode.fullAccess
        : CodingApprovalMode.defaultPermissions;
  }
}
