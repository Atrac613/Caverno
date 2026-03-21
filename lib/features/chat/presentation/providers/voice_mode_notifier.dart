import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/voice_recorder.dart';
import '../../../../core/services/voicevox_audio_player.dart';
import '../../../../core/services/voicevox_service.dart';
import '../../../../core/services/whisper_service.dart';
import '../../../../core/utils/content_parser.dart';
import '../../../../core/utils/logger.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/message.dart';
import 'chat_notifier.dart';
import 'chat_state.dart';

/// State of the voice mode loop.
enum VoiceModeStatus {
  idle,
  listening, // Recording microphone input
  processing, // Sending text to LLM
  speaking, // Synthesizing and playing audio
  error,
}

/// Holds the current state for the voice mode UI.
class VoiceModeState {
  const VoiceModeState({
    required this.status,
    this.transcript = '',
    this.errorMessage,
  });

  final VoiceModeStatus status;
  final String transcript;
  final String? errorMessage;

  VoiceModeState copyWith({
    VoiceModeStatus? status,
    String? transcript,
    String? errorMessage,
  }) {
    return VoiceModeState(
      status: status ?? this.status,
      transcript: transcript ?? this.transcript,
      errorMessage: errorMessage,
    );
  }
}

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = VoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

final whisperServiceProvider = Provider<WhisperService>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  return WhisperService(baseUrl: settings.whisperUrl);
});

final voicevoxServiceProvider = Provider<VoicevoxService>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  return VoicevoxService(baseUrl: settings.voicevoxUrl);
});

final voicevoxAudioPlayerProvider = Provider<VoicevoxAudioPlayer>((ref) {
  final player = VoicevoxAudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

final voiceModeNotifierProvider =
    StateNotifierProvider<VoiceModeNotifier, VoiceModeState>((ref) {
  return VoiceModeNotifier(
    ref.read(voiceRecorderProvider),
    ref.watch(whisperServiceProvider),
    ref.watch(voicevoxServiceProvider),
    ref.read(voicevoxAudioPlayerProvider),
    ref.read(chatNotifierProvider.notifier),
    () => ref.read(settingsNotifierProvider),
  );
});

class VoiceModeNotifier extends StateNotifier<VoiceModeState> {
  VoiceModeNotifier(
    this._recorder,
    this._whisperService,
    this._voicevoxService,
    this._audioPlayer,
    this._chatNotifier,
    this._getSettings,
  ) : super(const VoiceModeState(status: VoiceModeStatus.idle)) {
    _recorder.onSpeechEnd = _onSpeechRecorded;
    _recorder.onSpeechDetected = _onBargeInDetected;
    _recorder.onAmplitudeChanged = (rms) {
      final current = audioLevel.value;
      audioLevel.value = current + (rms - current) * 0.5;
    };
    _audioPlayer.onQueueComplete = _onAudioPlaybackComplete;
  }

  final VoiceRecorder _recorder;
  final WhisperService _whisperService;
  final VoicevoxService _voicevoxService;
  final VoicevoxAudioPlayer _audioPlayer;
  final ChatNotifier _chatNotifier;
  final AppSettings Function() _getSettings;

  StreamSubscription? _chatSubscription;
  String _currentlySynthesizingText = '';
  final _sentenceSplitRegExp = RegExp(r'[。！？\n]+');
  final ValueNotifier<double> audioLevel = ValueNotifier(0.0);
  Timer? _silencePromptTimer;
  bool _isFirstListen = false;
  int _consecutiveSynthesisErrors = 0;

  /// Max consecutive TTS failures before entering error state.
  static const int _maxConsecutiveSynthesisErrors = 3;

  @override
  void dispose() {
    _silencePromptTimer?.cancel();
    _chatSubscription?.cancel();
    _recorder.stopRecording();
    _audioPlayer.stop();
    audioLevel.dispose();
    super.dispose();
  }

  /// Start the voice mode loop.
  Future<void> start() async {
    if (state.status != VoiceModeStatus.idle &&
        state.status != VoiceModeStatus.error) {
      return;
    }

    _isFirstListen = true;
    _consecutiveSynthesisErrors = 0;

    // Subscribe to chat updates to intercept streaming responses.
    _chatSubscription = _chatNotifier.stream.listen(_onChatStateUpdated);

    await _startListening();
  }

  /// Stop the voice mode loop completely.
  Future<void> stop() async {
    _silencePromptTimer?.cancel();
    _silencePromptTimer = null;
    await _chatSubscription?.cancel();
    _chatSubscription = null;
    await _recorder.stopRecording();
    await _audioPlayer.stop();
    _currentlySynthesizingText = '';
    audioLevel.value = 0.0;
    state = const VoiceModeState(status: VoiceModeStatus.idle);
  }

  Future<void> _startListening() async {
    audioLevel.value = 0.0;
    state = const VoiceModeState(status: VoiceModeStatus.listening);

    final granted = await _recorder.startRecording();
    if (!granted) {
      state = const VoiceModeState(
        status: VoiceModeStatus.error,
        errorMessage: 'Microphone permission denied',
      );
      return;
    }
    
    if (_isFirstListen) {
      _silencePromptTimer?.cancel();
      _silencePromptTimer = Timer(const Duration(seconds: 6), () {
        if (state.status == VoiceModeStatus.listening) {
          appLog('[VoiceModeNotifier] Initial silence detected (6s). Sending hidden prompt.');
          _isFirstListen = false;
          state = state.copyWith(status: VoiceModeStatus.processing);
          
          final settings = _getSettings();
          final localeLang = PlatformDispatcher.instance.locale.languageCode;
          final resolvedLang = settings.language == 'system' ? localeLang : settings.language;
          
          _chatNotifier.sendHiddenPrompt(
            'The user is currently silent. Please say something brief and caring to prompt them. Respond in language code: $resolvedLang',
            isVoiceMode: true,
            languageCode: resolvedLang,
          );
        }
      });
    }
  }

  Future<void> _onSpeechRecorded(Uint8List wavBytes) async {
    _silencePromptTimer?.cancel();
    _isFirstListen = false;

    if (state.status != VoiceModeStatus.listening) return;

    state = state.copyWith(
      status: VoiceModeStatus.processing,
      transcript: 'Transcribing...',
    );

    try {
      final text = await _whisperService.transcribe(wavBytes);
      if (text.isEmpty) {
        // Nothing heard, go back to listening.
        await _startListening();
        return;
      }

      state = state.copyWith(transcript: text);
      _currentlySynthesizingText = '';
      
      // Send the text to the chat.
      final settings = _getSettings();
      final localeLang = PlatformDispatcher.instance.locale.languageCode;
      final resolvedLang = settings.language == 'system' ? localeLang : settings.language;
      
      await _chatNotifier.sendMessage(
        text,
        isVoiceMode: true,
        languageCode: resolvedLang,
      );
      
    } catch (e) {
      appLog('[VoiceModeNotifier] STT Error: $e');
      state = state.copyWith(
        status: VoiceModeStatus.error,
        errorMessage: 'Speech-to-text failed: $e',
      );
    }
  }

  /// Called automatically when the LLM chat state updates.
  void _onChatStateUpdated(ChatState chatState) {
    if (state.status != VoiceModeStatus.processing && 
        state.status != VoiceModeStatus.speaking) {
      return;
    }

    final messages = chatState.messages;
    if (messages.isEmpty) return;

    final lastMsg = messages.last;
    if (lastMsg.role != MessageRole.assistant) return;

    if (chatState.isLoading || lastMsg.isStreaming) {
      _processStreamingText(lastMsg.content, isFinal: false);
    } else {
      // Final update
      _processStreamingText(lastMsg.content, isFinal: true);
    }
  }

  Future<void> _processStreamingText(String rawContent, {required bool isFinal}) async {
    // 1. Strip out tool calls and thought blocks using the parser.
    final parsedChunks = ContentParser.parse(rawContent);
    final cleanTextBuffer = StringBuffer();
    for (final chunk in parsedChunks.segments) {
      if (chunk.type == ContentType.text) {
        cleanTextBuffer.write(chunk.content);
      }
    }
    final cleanText = cleanTextBuffer.toString();

    int matchLen = _currentlySynthesizingText.length;
    if (cleanText.length < matchLen) {
      matchLen = cleanText.length;
      _currentlySynthesizingText = cleanText;
    } else if (!cleanText.startsWith(_currentlySynthesizingText)) {
      // If the prefix string doesn't match perfectly (e.g. whitespace changes
      // from ContentParser incrementally stripping tags), just trust the length.
      // This explicitly prevents the double-playback/re-synthesizing bug!
      appLog('[VoiceModeNotifier] Minor mismatch detected, skipping reset to avoid double synthesis.');
    }
    
    final newText = cleanText.substring(matchLen);
    if (newText.isEmpty) {
      if (isFinal && _audioPlayer.isActive == false) {
        // Everything parsed and audio is done -> ready to listen again
        await _startListening();
      }
      return;
    }

    // Look for sentence boundaries in the new text
    int lastSentenceEnd = 0;
    final matches = _sentenceSplitRegExp.allMatches(newText);
    
    for (final match in matches) {
      final sentence = newText.substring(lastSentenceEnd, match.end);
      lastSentenceEnd = match.end;
      _currentlySynthesizingText += sentence;
      await _synthesizeAndQueue(sentence);
    }

    // If this is the final chunk, synthesize whatever is left
    if (isFinal && lastSentenceEnd < newText.length) {
      final remainder = newText.substring(lastSentenceEnd);
      _currentlySynthesizingText += remainder;
      await _synthesizeAndQueue(remainder);
    }
    
    if (isFinal && _audioPlayer.isActive == false) {
       await _startListening();
    }
  }

  Future<void> _synthesizeAndQueue(String sentence) async {
    final cleanSentence = sentence.trim();
    if (cleanSentence.isEmpty) return;

    if (state.status != VoiceModeStatus.speaking) {
      state = state.copyWith(status: VoiceModeStatus.speaking);
      // As soon as we start speaking, start monitoring for barge-in.
      final monitorOk = await _recorder.startMonitoring();
      if (!monitorOk) {
        appLog('[VoiceModeNotifier] Barge-in monitoring unavailable (mic permission denied)');
      }
    }

    try {
      final wavBytes = await _voicevoxService.synthesize(
        cleanSentence,
        speakerId: _getSettings().voicevoxSpeakerId,
      );
      _consecutiveSynthesisErrors = 0;
      _audioPlayer.enqueue(wavBytes);
    } catch (e) {
      _consecutiveSynthesisErrors++;
      appLog('[VoiceModeNotifier] Synthesis error ($_consecutiveSynthesisErrors/$_maxConsecutiveSynthesisErrors): $e');
      if (_consecutiveSynthesisErrors >= _maxConsecutiveSynthesisErrors) {
        await _audioPlayer.stop();
        await _recorder.stopRecording();
        state = const VoiceModeState(
          status: VoiceModeStatus.error,
          errorMessage: 'VOICEVOX synthesis failed repeatedly',
        );
      }
    }
  }

  void _onBargeInDetected() {
    _silencePromptTimer?.cancel();
    _isFirstListen = false;

    if (state.status != VoiceModeStatus.speaking) return;

    appLog('[VoiceModeNotifier] Barge-in! Interrupting LLM and TTS.');
    
    // Stop audio.
    _audioPlayer.stop();
    
    // Cancel LLM streaming.
    _chatNotifier.cancelStreaming();
    
    // Restart listening.
    _startListening();
  }

  void _onAudioPlaybackComplete() {
    if (state.status != VoiceModeStatus.speaking) return;
    
    // Only restart listening if the LLM has also finished streaming its output.
    if (!_chatNotifier.state.isLoading) {
       _startListening();
    }
  }
}
