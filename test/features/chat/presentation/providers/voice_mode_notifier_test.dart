import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/voice_recorder.dart';
import 'package:caverno/core/services/voicevox_audio_player.dart';
import 'package:caverno/core/services/voicevox_service.dart';
import 'package:caverno/core/services/whisper_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/voice_mode_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class MockVoiceRecorder extends Mock implements VoiceRecorder {}

class MockWhisperService extends Mock implements WhisperService {}

class MockVoicevoxService extends Mock implements VoicevoxService {}

class MockVoicevoxAudioPlayer extends Mock implements VoicevoxAudioPlayer {}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      language: 'en',
    );
  }
}

class _ControllableChatNotifier extends ChatNotifier {
  final List<String> sentMessages = [];
  final List<String> hiddenPrompts = [];
  bool cancelCalled = false;

  @override
  ChatState build() => ChatState.initial();

  @override
  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
  }) async {
    sentMessages.add(content);
  }

  @override
  Future<void> sendHiddenPrompt(
    String instruction, {
    bool isVoiceMode = false,
    String languageCode = 'en',
  }) async {
    hiddenPrompts.add(instruction);
  }

  @override
  void cancelStreaming() {
    cancelCalled = true;
  }

  void emit(ChatState nextState) {
    state = nextState;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  late MockVoiceRecorder mockRecorder;
  late MockWhisperService mockWhisper;
  late MockVoicevoxService mockVoicevox;
  late MockVoicevoxAudioPlayer mockPlayer;
  late ProviderContainer container;
  late VoiceModeNotifier notifier;
  late _ControllableChatNotifier chatNotifier;
  Future<void> Function(Uint8List wavBytes)? speechEndHandler;
  void Function()? queueCompleteHandler;

  setUp(() {
    mockRecorder = MockVoiceRecorder();
    mockWhisper = MockWhisperService();
    mockVoicevox = MockVoicevoxService();
    mockPlayer = MockVoicevoxAudioPlayer();

    // Default stubs for recorder callbacks (setters).
    when(() => mockRecorder.onSpeechEnd = any()).thenAnswer((invocation) {
      speechEndHandler =
          invocation.positionalArguments.first
              as Future<void> Function(Uint8List wavBytes)?;
    });
    when(() => mockRecorder.onSpeechDetected = any()).thenReturn(null);
    when(() => mockRecorder.onAmplitudeChanged = any()).thenReturn(null);
    when(() => mockPlayer.onQueueComplete = any()).thenAnswer((invocation) {
      queueCompleteHandler =
          invocation.positionalArguments.first as void Function()?;
    });
    when(() => mockRecorder.stopRecording()).thenAnswer((_) async {});
    when(() => mockPlayer.stop()).thenAnswer((_) async {});
    when(() => mockPlayer.isActive).thenReturn(false);
    when(() => mockPlayer.enqueue(any())).thenReturn(null);

    container = ProviderContainer(
      overrides: [
        voiceRecorderProvider.overrideWithValue(mockRecorder),
        whisperServiceProvider.overrideWithValue(mockWhisper),
        voicevoxServiceProvider.overrideWithValue(mockVoicevox),
        voicevoxAudioPlayerProvider.overrideWithValue(mockPlayer),
        chatNotifierProvider.overrideWith(_ControllableChatNotifier.new),
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
      ],
    );
    notifier = container.read(voiceModeNotifierProvider.notifier);
    chatNotifier =
        container.read(chatNotifierProvider.notifier)
            as _ControllableChatNotifier;
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

  group('chat loading handoff', () {
    test(
      'waits for chat loading to finish before resuming listening',
      () async {
        when(() => mockRecorder.startRecording()).thenAnswer((_) async => true);
        when(
          () => mockWhisper.transcribe(any()),
        ).thenAnswer((_) async => 'Check the host status');
        when(
          () => mockVoicevox.synthesize(
            any(),
            speakerId: any(named: 'speakerId'),
          ),
        ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));

        await notifier.start();
        expect(notifier.state.status, VoiceModeStatus.listening);
        expect(speechEndHandler, isNotNull);
        await Future<void>.delayed(const Duration(milliseconds: 900));

        await speechEndHandler!(Uint8List.fromList([9, 9, 9]));
        expect(chatNotifier.sentMessages, ['Check the host status']);
        expect(notifier.state.status, VoiceModeStatus.processing);

        chatNotifier.emit(
          ChatState(
            messages: [
              Message(
                id: 'assistant-streaming',
                content: 'Ready\n',
                role: MessageRole.assistant,
                timestamp: DateTime(2026),
                isStreaming: true,
              ),
            ],
            isLoading: true,
            error: null,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(notifier.state.status, VoiceModeStatus.speaking);
        expect(queueCompleteHandler, isNotNull);

        queueCompleteHandler!.call();
        await Future<void>.delayed(Duration.zero);

        expect(notifier.state.status, VoiceModeStatus.speaking);
        verify(() => mockRecorder.startRecording()).called(1);

        chatNotifier.emit(
          ChatState(
            messages: [
              Message(
                id: 'assistant-final',
                content: 'Ready\n',
                role: MessageRole.assistant,
                timestamp: DateTime(2026),
              ),
            ],
            isLoading: false,
            error: null,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(notifier.state.status, VoiceModeStatus.listening);
        verify(() => mockRecorder.startRecording()).called(1);
      },
    );
  });
}
