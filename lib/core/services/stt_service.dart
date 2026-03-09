import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Speech-to-Text service
/// Manages voice input
class SttService {
  static const MethodChannel _privacyChannel = MethodChannel(
    'com.noguwo.apps.caverno/privacy',
  );
  final SpeechToText _stt = SpeechToText();
  bool _isListening = false;
  bool _isInitialized = false;
  bool _isAvailable = false;
  Future<bool>? _initFuture;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  bool get isAvailable => _isAvailable;

  /// Initialize
  Future<bool> init() async {
    if (_isInitialized) return _isAvailable;
    if (_initFuture != null) return _initFuture!;

    _initFuture = _initInternal();
    try {
      return await _initFuture!;
    } finally {
      _initFuture = null;
    }
  }

  Future<bool> _initInternal() async {
    try {
      if (!await _validateMacOSSpeechPrivacyConfig()) {
        _isAvailable = false;
        return _isAvailable;
      }

      _isAvailable = await _stt.initialize(
        onStatus: (status) {
          print('[STT] Status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
        onError: (error) {
          print('[STT] Error: ${error.errorMsg}');
          _isListening = false;
        },
      );
    } catch (e) {
      print('[STT] Initialization exception: $e');
      _isAvailable = false;
    } finally {
      _isInitialized = true;
    }
    return _isAvailable;
  }

  Future<bool> _validateMacOSSpeechPrivacyConfig() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return true;
    }

    try {
      final result = await _privacyChannel.invokeMapMethod<String, dynamic>(
        'getSpeechUsageDescriptions',
      );
      if (result == null) return true;

      final hasSpeech = result['hasSpeech'] == true;
      final hasMicrophone = result['hasMicrophone'] == true;
      final isCodexHost = result['isCodexHost'] == true;
      if (isCodexHost) {
        print(
          '[STT] Detected running on Codex/Antigravity. '
          'Disabling macOS speech input because speech permission '
          'belongs to the host and causes a TCC crash.',
        );
        return false;
      }

      if (!hasSpeech || !hasMicrophone) {
        print(
          '[STT] Missing macOS usage descriptions: '
          'NSSpeechRecognitionUsageDescription=$hasSpeech, '
          'NSMicrophoneUsageDescription=$hasMicrophone',
        );
        return false;
      }
      return true;
    } on MissingPluginException {
      return true;
    } catch (e) {
      print('[STT] macOS privacy pre-check failed: $e');
      return false;
    }
  }

  /// Start speech recognition
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  }) async {
    if (!_isInitialized) {
      final available = await init();
      if (!available) {
        print('[STT] Speech recognition is not available');
        return;
      }
    }

    if (!_isAvailable) {
      print('[STT] Speech recognition is not available');
      return;
    }

    if (_isListening) {
      await stopListening();
    }

    _isListening = true;

    await _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords, result.finalResult);
        if (result.finalResult) {
          _isListening = false;
          onDone?.call();
        }
      },
      localeId: 'ja_JP',
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
        partialResults: true,
      ),
    );
  }

  /// Stop speech recognition
  Future<void> stopListening() async {
    _isListening = false;
    await _stt.stop();
  }

  /// Get available locales
  Future<List<LocaleName>> getAvailableLocales() async {
    if (!_isInitialized) await init();
    return _stt.locales();
  }

  /// Release resources
  Future<void> dispose() async {
    await stopListening();
  }
}
