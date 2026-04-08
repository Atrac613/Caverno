import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/voice_recorder.dart';
import 'package:caverno/core/services/voicevox_audio_player.dart';
import 'package:caverno/core/services/voicevox_service.dart';
import 'package:caverno/core/services/whisper_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/voice_mode_notifier.dart';

class MockVoiceRecorder extends Mock implements VoiceRecorder {}

class MockWhisperService extends Mock implements WhisperService {}

class MockVoicevoxService extends Mock implements VoicevoxService {}

class MockVoicevoxAudioPlayer extends Mock implements VoicevoxAudioPlayer {}

/// A no-op [ChatNotifier] used to satisfy [chatNotifierProvider] in tests
/// without invoking the real dependency graph.
class _FakeChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

void main() {
  late MockVoiceRecorder mockRecorder;
  late MockWhisperService mockWhisper;
  late MockVoicevoxService mockVoicevox;
  late MockVoicevoxAudioPlayer mockPlayer;
  late ProviderContainer container;
  late VoiceModeNotifier notifier;

  setUp(() {
    mockRecorder = MockVoiceRecorder();
    mockWhisper = MockWhisperService();
    mockVoicevox = MockVoicevoxService();
    mockPlayer = MockVoicevoxAudioPlayer();

    // Default stubs for recorder callbacks (setters).
    when(() => mockRecorder.onSpeechEnd = any()).thenReturn(null);
    when(() => mockRecorder.onSpeechDetected = any()).thenReturn(null);
    when(() => mockRecorder.onAmplitudeChanged = any()).thenReturn(null);
    when(() => mockPlayer.onQueueComplete = any()).thenReturn(null);
    when(() => mockRecorder.stopRecording()).thenAnswer((_) async {});
    when(() => mockPlayer.stop()).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        voiceRecorderProvider.overrideWithValue(mockRecorder),
        whisperServiceProvider.overrideWithValue(mockWhisper),
        voicevoxServiceProvider.overrideWithValue(mockVoicevox),
        voicevoxAudioPlayerProvider.overrideWithValue(mockPlayer),
        chatNotifierProvider.overrideWith(_FakeChatNotifier.new),
      ],
    );
    notifier = container.read(voiceModeNotifierProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  group('start()', () {
    test('enters listening state when mic permission granted', () async {
      when(() => mockRecorder.startRecording()).thenAnswer((_) async => true);

      await notifier.start();

      expect(notifier.state.status, VoiceModeStatus.listening);
      expect(notifier.state.errorMessage, isNull);
    });

    test('enters error state when mic permission denied', () async {
      when(() => mockRecorder.startRecording()).thenAnswer((_) async => false);

      await notifier.start();

      expect(notifier.state.status, VoiceModeStatus.error);
      expect(notifier.state.errorMessage, contains('permission'));
    });
  });

  group('stop()', () {
    test('resets state to idle and cleans up resources', () async {
      when(() => mockRecorder.startRecording()).thenAnswer((_) async => true);

      await notifier.start();
      await notifier.stop();

      expect(notifier.state.status, VoiceModeStatus.idle);
      verify(() => mockRecorder.stopRecording()).called(greaterThan(0));
      verify(() => mockPlayer.stop()).called(greaterThan(0));
    });
  });

  group('initial state', () {
    test('starts with idle status', () {
      expect(notifier.state.status, VoiceModeStatus.idle);
      expect(notifier.state.transcript, '');
      expect(notifier.state.errorMessage, isNull);
    });
  });
}
