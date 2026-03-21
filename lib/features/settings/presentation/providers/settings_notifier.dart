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
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
      final repository = ref.watch(settingsRepositoryProvider);
      final fileService = ref.watch(settingsFileServiceProvider);
      final qrService = ref.watch(settingsQrServiceProvider);
      return SettingsNotifier(repository, fileService, qrService);
    });

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._repository, this._fileService, this._qrService) : super(_repository.load());

  final SettingsRepository _repository;
  final SettingsFileService _fileService;
  final SettingsQrService _qrService;

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
    state = state.copyWith(mcpUrl: mcpUrl);
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
