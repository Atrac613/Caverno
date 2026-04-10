import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../data/settings_file_service.dart';
import '../../data/settings_qr_service.dart';
import '../../data/settings_repository.dart';
import '../../domain/entities/app_settings.dart';

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

  Future<void> updateMcpUrl(String mcpUrl) async {
    await updateMcpUrls(mcpUrl.isEmpty ? const [] : [mcpUrl]);
  }

  Future<void> updateMcpUrls(List<String> mcpUrls) async {
    await updateMcpServers(AppSettings.buildMcpServersFromUrls(mcpUrls));
  }

  Future<void> updateMcpServers(List<McpServerConfig> mcpServers) async {
    final activeUrls = AppSettings.activeMcpUrlsFromServers(mcpServers);
    state = state.copyWith(
      mcpUrl: activeUrls.isEmpty ? '' : activeUrls.first,
      mcpUrls: activeUrls,
      mcpServers: List<McpServerConfig>.from(mcpServers),
    );
    await _repository.save(state);
  }

  Future<void> addMcpServer() async {
    await updateMcpServers([
      ...state.configuredMcpServers,
      const McpServerConfig(),
    ]);
  }

  Future<void> updateMcpServerUrl(int index, String url) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    servers[index] = servers[index].copyWith(url: url);
    await updateMcpServers(servers);
  }

  Future<void> updateMcpServerEnabled(int index, bool enabled) async {
    final servers = List<McpServerConfig>.from(state.configuredMcpServers);
    if (index < 0 || index >= servers.length) return;
    servers[index] = servers[index].copyWith(enabled: enabled);
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

  Future<void> updateDemoMode(bool demoMode) async {
    state = state.copyWith(demoMode: demoMode);
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
}
