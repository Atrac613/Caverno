import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/voice_recorder.dart';
import 'package:caverno/core/services/voicevox_audio_player.dart';
import 'package:caverno/core/services/voicevox_service.dart';
import 'package:caverno/core/services/whisper_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/voice_mode_notifier.dart';

class MockVoiceRecorder extends Mock implements VoiceRecorder {}

class MockWhisperService extends Mock implements WhisperService {}

class MockVoicevoxService extends Mock implements VoicevoxService {}

class MockVoicevoxAudioPlayer extends Mock implements VoicevoxAudioPlayer {}

class MockChatNotifier extends Mock implements ChatNotifier {}

void main() {
  late MockVoiceRecorder mockRecorder;
  late MockWhisperService mockWhisper;
  late MockVoicevoxService mockVoicevox;
  late MockVoicevoxAudioPlayer mockPlayer;
  late MockChatNotifier mockChat;
  late VoiceModeNotifier notifier;

  setUp(() {
    mockRecorder = MockVoiceRecorder();
    mockWhisper = MockWhisperService();
    mockVoicevox = MockVoicevoxService();
    mockPlayer = MockVoicevoxAudioPlayer();
    mockChat = MockChatNotifier();

    // Default stubs for recorder callbacks (setters).
    when(() => mockRecorder.onSpeechEnd = any()).thenReturn(null);
    when(() => mockRecorder.onSpeechDetected = any()).thenReturn(null);
    when(() => mockRecorder.onAmplitudeChanged = any()).thenReturn(null);
    when(() => mockPlayer.onQueueComplete = any()).thenReturn(null);
    when(() => mockRecorder.stopRecording()).thenAnswer((_) async {});
    when(() => mockPlayer.stop()).thenAnswer((_) async {});
    when(() => mockChat.stream).thenAnswer((_) => const Stream.empty());

    notifier = VoiceModeNotifier(
      mockRecorder,
      mockWhisper,
      mockVoicevox,
      mockPlayer,
      mockChat,
      0,
    );
  });

  tearDown(() {
    notifier.dispose();
  });

  group('start()', () {
    test('enters listening state when all services available', () async {
      when(() => mockWhisper.isAvailable()).thenAnswer((_) async => true);
      when(() => mockVoicevox.isAvailable()).thenAnswer((_) async => true);
      when(() => mockRecorder.startRecording()).thenAnswer((_) async => true);

      await notifier.start();

      expect(notifier.state.status, VoiceModeStatus.listening);
      expect(notifier.state.errorMessage, isNull);
    });

    test('enters error state when Whisper is unavailable', () async {
      when(() => mockWhisper.isAvailable()).thenAnswer((_) async => false);
      when(() => mockWhisper.baseUrl).thenReturn('http://localhost:8080');
      when(() => mockVoicevox.isAvailable()).thenAnswer((_) async => true);
      when(() => mockVoicevox.baseUrl).thenReturn('http://localhost:50021');

      await notifier.start();

      expect(notifier.state.status, VoiceModeStatus.error);
      expect(notifier.state.errorMessage, contains('Whisper'));
    });

    test('enters error state when VOICEVOX is unavailable', () async {
      when(() => mockWhisper.isAvailable()).thenAnswer((_) async => true);
      when(() => mockWhisper.baseUrl).thenReturn('http://localhost:8080');
      when(() => mockVoicevox.isAvailable()).thenAnswer((_) async => false);
      when(() => mockVoicevox.baseUrl).thenReturn('http://localhost:50021');

      await notifier.start();

      expect(notifier.state.status, VoiceModeStatus.error);
      expect(notifier.state.errorMessage, contains('VOICEVOX'));
    });

    test('reports both services when both are unavailable', () async {
      when(() => mockWhisper.isAvailable()).thenAnswer((_) async => false);
      when(() => mockWhisper.baseUrl).thenReturn('http://localhost:8080');
      when(() => mockVoicevox.isAvailable()).thenAnswer((_) async => false);
      when(() => mockVoicevox.baseUrl).thenReturn('http://localhost:50021');

      await notifier.start();

      expect(notifier.state.status, VoiceModeStatus.error);
      expect(notifier.state.errorMessage, contains('Whisper'));
      expect(notifier.state.errorMessage, contains('VOICEVOX'));
    });

    test('enters error state when mic permission denied', () async {
      when(() => mockWhisper.isAvailable()).thenAnswer((_) async => true);
      when(() => mockVoicevox.isAvailable()).thenAnswer((_) async => true);
      when(() => mockRecorder.startRecording()).thenAnswer((_) async => false);

      await notifier.start();

      expect(notifier.state.status, VoiceModeStatus.error);
      expect(notifier.state.errorMessage, contains('permission'));
    });
  });

  group('stop()', () {
    test('resets state to idle and cleans up resources', () async {
      when(() => mockWhisper.isAvailable()).thenAnswer((_) async => true);
      when(() => mockVoicevox.isAvailable()).thenAnswer((_) async => true);
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
