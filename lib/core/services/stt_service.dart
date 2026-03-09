import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Speech-to-Text サービス
/// 音声入力を管理
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

  /// 初期化
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
          print('[STT] ステータス: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
        onError: (error) {
          print('[STT] エラー: ${error.errorMsg}');
          _isListening = false;
        },
      );
    } catch (e) {
      print('[STT] 初期化例外: $e');
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
          '[STT] Codex/Antigravity上での実行を検出。'
          'speech permission がホスト側へ帰属して TCC クラッシュするため'
          'macOS音声入力を無効化します。',
        );
        return false;
      }

      if (!hasSpeech || !hasMicrophone) {
        print(
          '[STT] macOS usage description不足: '
          'NSSpeechRecognitionUsageDescription=$hasSpeech, '
          'NSMicrophoneUsageDescription=$hasMicrophone',
        );
        return false;
      }
      return true;
    } on MissingPluginException {
      return true;
    } catch (e) {
      print('[STT] macOS privacy事前チェック失敗: $e');
      return false;
    }
  }

  /// 音声認識を開始
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  }) async {
    if (!_isInitialized) {
      final available = await init();
      if (!available) {
        print('[STT] 音声認識は利用できません');
        return;
      }
    }

    if (!_isAvailable) {
      print('[STT] 音声認識は利用できません');
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

  /// 音声認識を停止
  Future<void> stopListening() async {
    _isListening = false;
    await _stt.stop();
  }

  /// 利用可能なロケールを取得
  Future<List<LocaleName>> getAvailableLocales() async {
    if (!_isInitialized) await init();
    return _stt.locales();
  }

  /// リソースを解放
  Future<void> dispose() async {
    await stopListening();
  }
}
