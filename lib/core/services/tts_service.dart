import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech サービス
/// アシスタントメッセージの読み上げを管理
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _isInitialized;

  /// 初期化
  Future<void> init() async {
    if (_isInitialized) return;

    await _tts.setLanguage('ja-JP');
    await _tts.setSpeechRate(1.0);
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
      print('[TTS] エラー: $msg');
    });

    _isInitialized = true;
  }

  /// テキストを読み上げる
  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    if (_isSpeaking) await stop();

    if (text.isEmpty) return;

    _isSpeaking = true;
    await _tts.speak(text);
  }

  /// 読み上げを停止
  Future<void> stop() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  /// 読み上げ速度を設定 (0.5 - 2.0)
  Future<void> setSpeechRate(double rate) async {
    final clampedRate = rate.clamp(0.5, 2.0);
    await _tts.setSpeechRate(clampedRate);
  }

  /// 言語を設定
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  /// 利用可能な言語を取得
  Future<List<String>> getAvailableLanguages() async {
    final languages = await _tts.getLanguages;
    return languages.cast<String>();
  }

  /// リソースを解放
  Future<void> dispose() async {
    await stop();
  }
}
