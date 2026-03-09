import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stt_service.dart';
import 'tts_service.dart';

/// TTS サービスプロバイダー
final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});

/// STT サービスプロバイダー
final sttServiceProvider = Provider<SttService>((ref) {
  final service = SttService();
  ref.onDispose(() => service.dispose());
  return service;
});
