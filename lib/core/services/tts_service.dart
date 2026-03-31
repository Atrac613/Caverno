import 'package:flutter_tts/flutter_tts.dart';
import '../utils/logger.dart';

/// Text-to-Speech service
/// Manages reading aloud of assistant messages
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _isInitialized;

  /// Initialize
  Future<void> init() async {
    if (_isInitialized) return;

    await _tts.setLanguage('ja-JP');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _tts.setCancelHandler(() {
      _isSpeaking = false;
    });

    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      appLog('[TTS] Error: $msg');
    });

    _isInitialized = true;
  }

  /// Speak the given text
  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    if (_isSpeaking) await stop();

    if (text.isEmpty) return;

    _isSpeaking = true;
    await _tts.speak(text);
  }

  /// Stop speaking
  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  /// Set speech rate (0.0 - 1.0, where 0.5 is normal speed)
  Future<void> setSpeechRate(double rate) async {
    final clampedRate = rate.clamp(0.0, 1.0);
    await _tts.setSpeechRate(clampedRate);
  }

  /// Set language
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  /// Get available languages
  Future<List<String>> getAvailableLanguages() async {
    final languages = await _tts.getLanguages;
    return languages.cast<String>();
  }

  /// Release resources
  Future<void> dispose() async {
    await stop();
  }
}
