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
import '../../../settings/domain/services/app_language_resolver.dart';
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
    NotifierProvider<VoiceModeNotifier, VoiceModeState>(VoiceModeNotifier.new);

class VoiceModeNotifier extends Notifier<VoiceModeState> {
  late final VoiceRecorder _recorder;
  late final WhisperService _whisperService;
  late final VoicevoxService _voicevoxService;
  late final VoicevoxAudioPlayer _audioPlayer;
  late final ChatNotifier _chatNotifier;

  AppSettings _getSettings() => ref.read(settingsNotifierProvider);

  @override
  VoiceModeState build() {
    _recorder = ref.read(voiceRecorderProvider);
    _whisperService = ref.read(whisperServiceProvider);
    _voicevoxService = ref.read(voicevoxServiceProvider);
    _audioPlayer = ref.read(voicevoxAudioPlayerProvider);
    _chatNotifier = ref.read(chatNotifierProvider.notifier);

    _recorder.onSpeechEnd = _onSpeechRecorded;
    _recorder.onSpeechDetected = _onBargeInDetected;
    _recorder.onAmplitudeChanged = (rms) {
      final current = audioLevel.value;
      audioLevel.value = current + (rms - current) * 0.5;
    };
    _audioPlayer.onQueueComplete = _onAudioPlaybackComplete;

    // Always observe chat state; the handler is a no-op outside of the
    // processing/speaking phases. Riverpod auto-disposes the subscription
    // with the notifier.
    ref.listen<ChatState>(
      chatNotifierProvider,
      (previous, next) => _onChatStateUpdated(next),
    );

    ref.onDispose(_handleDispose);

    return const VoiceModeState(status: VoiceModeStatus.idle);
  }
  String _currentlySynthesizingText = '';
  final _sentenceSplitRegExp = RegExp(r'[。！？\n]+');
  final ValueNotifier<double> audioLevel = ValueNotifier(0.0);
  Timer? _silencePromptTimer;
  bool _isFirstListen = false;
  int _consecutiveSynthesisErrors = 0;
  bool _hasNotifiedToolUseThisTurn = false;

  Stopwatch? _llmStopwatch;
  bool _isFirstTokenLogged = false;

  /// Serializes access to [_processStreamingText] so concurrent stream
  /// updates don't duplicate synthesis calls.
  bool _isProcessingStream = false;
  bool _hasPendingStreamUpdate = false;
  String _latestRawContent = '';
  bool _latestIsFinal = false;

  /// Grace period after TTS ends before speech detection is armed.
  /// Prevents residual speaker audio from triggering a false recording.
  static const Duration _postTtsGrace = Duration(milliseconds: 800);
  bool _speechDetectionArmed = true;

  /// Max consecutive TTS failures before entering error state.
  static const int _maxConsecutiveSynthesisErrors = 3;

  /// Patterns that Whisper outputs for non-speech audio (music, noise, etc.).
  /// These should be discarded rather than sent to the LLM.
  static final RegExp _nonSpeechPattern = RegExp(
    r'^\s*'                          // leading whitespace
    r'[\[\(（【]'                     // opening bracket
    r'[^\]\)）】]*'                   // content inside brackets
    r'(music|musik|musique|音楽|歌|bgm|blank.audio|noise|silence|applause|laughter|拍手|笑)'
    r'[^\]\)）】]*'                   // content inside brackets
    r'[\]\)）】]'                     // closing bracket
    r'\s*$',                          // trailing whitespace
    caseSensitive: false,
  );

  /// Known Whisper hallucination phrases produced from silence or faint noise.
  /// Whisper models commonly "hallucinate" YouTube-style phrases when the
  /// input audio contains little or no actual speech.
  static const List<String> _whisperHallucinations = [
    // Japanese
    'ご視聴ありがとうございました',
    'ご視聴ありがとうございます',
    'チャンネル登録お願いします',
    'チャンネル登録よろしくお願いします',
    'お疲れ様でした',
    '字幕は自動生成されています',
    'ではまた',
    'おやすみなさい',
    'はい',
    // English
    'thank you for watching',
    'thanks for watching',
    'please subscribe',
    'subscribe to my channel',
    'like and subscribe',
    'see you next time',
    'goodbye',
    // Chinese
    '谢谢观看',
    '谢谢大家',
    // Korean
    '시청해 주셔서 감사합니다',
  ];

  /// Phrases that this app synthesizes via TTS. If the microphone picks them
  /// up and Whisper transcribes them, they must be discarded as echo.
  static const List<String> _ownTtsPhrases = [
    '調べてみますね',
    '我来查一下',
    '확인해 볼게요',
    'let me check that for you',
  ];

  /// Check if Whisper output is non-speech noise (music markers, symbols, etc.)
  /// or a known hallucination from silence.
  static bool _isNonSpeechTranscription(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;

    // Pure music symbols: ♪, 🎵, 🎶, etc.
    if (RegExp(r'^[\s♪♫🎵🎶🎤～~…・、。,.]+$').hasMatch(trimmed)) return true;

    // Bracketed noise markers: [Music], (音楽), [BLANK_AUDIO], etc.
    if (_nonSpeechPattern.hasMatch(trimmed)) return true;

    // Known Whisper hallucination phrases from silence/noise
    // and own TTS phrases that may be picked up as echo.
    final lower = trimmed.toLowerCase().replaceAll(RegExp(r'[。！？!?.、,\s]+$'), '');
    for (final phrase in _whisperHallucinations) {
      if (lower == phrase.toLowerCase()) return true;
    }
    for (final phrase in _ownTtsPhrases) {
      if (lower == phrase.toLowerCase()) return true;
    }

    // Whisper hallucination: single repeated character/word
    // e.g. "ん ん ん ん", "あ あ あ", "... ... ..."
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length >= 3 && words.toSet().length == 1) return true;

    return false;
  }

  void _handleDispose() {
    _silencePromptTimer?.cancel();
    _recorder.stopRecording();
    _audioPlayer.stop();
    audioLevel.dispose();
  }

  /// Start the voice mode loop.
  Future<void> start() async {
    if (state.status != VoiceModeStatus.idle &&
        state.status != VoiceModeStatus.error) {
      return;
    }

    _isFirstListen = true;
    _consecutiveSynthesisErrors = 0;

    // Chat state observation is established in build(); no manual setup
    // is required here.

    await _startListening();
  }

  /// Stop the voice mode loop completely.
  Future<void> stop() async {
    _silencePromptTimer?.cancel();
    _silencePromptTimer = null;
    await _recorder.stopRecording();
    await _audioPlayer.stop();
    _currentlySynthesizingText = '';
    audioLevel.value = 0.0;
    state = const VoiceModeState(status: VoiceModeStatus.idle);
  }

  Future<void> _startListening() async {
    _hasNotifiedToolUseThisTurn = false;
    audioLevel.value = 0.0;
    _speechDetectionArmed = false;
    state = const VoiceModeState(status: VoiceModeStatus.listening);

    final granted = await _recorder.startRecording();
    if (!granted) {
      state = const VoiceModeState(
        status: VoiceModeStatus.error,
        errorMessage: 'Microphone permission denied',
      );
      return;
    }

    // Arm speech detection after a grace period so residual speaker audio
    // (TTS playback echo) does not immediately trigger a false recording.
    Future.delayed(_postTtsGrace, () {
      _speechDetectionArmed = true;
    });
    
    _silencePromptTimer?.cancel();
    if (_isFirstListen) {
      _silencePromptTimer = Timer(const Duration(seconds: 6), () {
        if (state.status == VoiceModeStatus.listening) {
          appLog('[VoiceModeNotifier] Initial silence detected (6s). Sending hidden prompt.');
          _isFirstListen = false;
          state = state.copyWith(status: VoiceModeStatus.processing);
          
          final settings = _getSettings();
          final resolvedLang = resolveAppLanguageCode(
            preference: settings.language,
            systemLocale: PlatformDispatcher.instance.locale,
          );
          
          _llmStopwatch = Stopwatch()..start();
          _isFirstTokenLogged = false;

          _chatNotifier.sendHiddenPrompt(
            'The user is currently silent. Please say something brief and caring to prompt them. Respond in language code: $resolvedLang',
            isVoiceMode: true,
            languageCode: resolvedLang,
          );
        }
      });
    } else {
      if (_getSettings().voiceModeAutoStop) {
        _silencePromptTimer = Timer(const Duration(seconds: 60), () {
          if (state.status == VoiceModeStatus.listening) {
            appLog('[VoiceModeNotifier] Subsequent silence detected (60s). Stopping voice mode.');
            stop();
          }
        });
      }
    }
  }

  Future<void> _onSpeechRecorded(Uint8List wavBytes) async {
    _silencePromptTimer?.cancel();
    _isFirstListen = false;

    if (state.status != VoiceModeStatus.listening) return;

    // Discard audio captured during the post-TTS grace period.
    if (!_speechDetectionArmed) {
      appLog('[VoiceModeNotifier] Discarding speech during grace period');
      await _startListening();
      return;
    }

    state = state.copyWith(
      status: VoiceModeStatus.processing,
      transcript: 'Transcribing...',
    );

    try {
      final sttStopwatch = Stopwatch()..start();
      final text = await _whisperService.transcribe(wavBytes);
      sttStopwatch.stop();
      appLog('[Performance] STT (Whisper) latency: ${sttStopwatch.elapsedMilliseconds}ms');

      if (text.isEmpty || _isNonSpeechTranscription(text)) {
        // Nothing heard or non-speech audio (music, noise, etc.).
        if (text.isNotEmpty) {
          appLog('[VoiceModeNotifier] Filtered non-speech transcription: "$text"');
        }
        await _startListening();
        return;
      }

      state = state.copyWith(transcript: text);
      _currentlySynthesizingText = '';
      
      // Send the text to the chat.
      final settings = _getSettings();
      final resolvedLang = resolveAppLanguageCode(
        preference: settings.language,
        systemLocale: PlatformDispatcher.instance.locale,
      );
      
      _llmStopwatch = Stopwatch()..start();
      _isFirstTokenLogged = false;

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

    final isFinal = !chatState.isLoading && !lastMsg.isStreaming;

    if (_llmStopwatch != null && !_isFirstTokenLogged && lastMsg.content.isNotEmpty) {
      _isFirstTokenLogged = true;
      appLog('[Performance] LLM TTFT (Time To First Token): ${_llmStopwatch!.elapsedMilliseconds}ms');
    }

    if (_llmStopwatch != null && isFinal) {
      _llmStopwatch!.stop();
      appLog('[Performance] LLM Total latency: ${_llmStopwatch!.elapsedMilliseconds}ms');
      _llmStopwatch = null;
    }

    _scheduleStreamProcessing(lastMsg.content, isFinal: isFinal);
  }

  /// Enqueue a stream processing request. Only the latest content matters
  /// because [_processStreamingText] diffs against [_currentlySynthesizingText].
  void _scheduleStreamProcessing(String rawContent, {required bool isFinal}) {
    _latestRawContent = rawContent;
    _latestIsFinal = isFinal;

    if (_isProcessingStream) {
      _hasPendingStreamUpdate = true;
      return;
    }

    _drainStreamQueue();
  }

  /// Process pending stream updates one at a time.
  Future<void> _drainStreamQueue() async {
    _isProcessingStream = true;
    try {
      do {
        _hasPendingStreamUpdate = false;
        final content = _latestRawContent;
        final isFinal = _latestIsFinal;
        await _processStreamingText(content, isFinal: isFinal);
      } while (_hasPendingStreamUpdate);
    } finally {
      _isProcessingStream = false;
    }
  }

  Future<void> _processStreamingText(String rawContent, {required bool isFinal}) async {
    // 1. Strip out tool calls and thought blocks using the parser.
    final parsedChunks = ContentParser.parse(rawContent);

    // 2. Play a brief notification if we just detected the start of a tool call
    if (!_hasNotifiedToolUseThisTurn) {
      final hasToolCall = parsedChunks.segments.any((s) => s.type == ContentType.toolCall) ||
          (parsedChunks.hasIncompleteTag && parsedChunks.incompleteTagType == 'tool_call');
      
      if (hasToolCall) {
        _hasNotifiedToolUseThisTurn = true;
        
        final settings = _getSettings();
        final resolvedLang = resolveAppLanguageCode(
          preference: settings.language,
          systemLocale: PlatformDispatcher.instance.locale,
        );
        
        final phrase = _getToolNotificationPhrase(resolvedLang);
        appLog('[VoiceModeNotifier] Tool use detected. Playing notification: $phrase');
        await _synthesizeAndQueue(phrase);
      }
    }

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
      // Stop any active recording/monitoring to avoid TTS audio feedback loop.
      await _recorder.stopRecording();
    }

    try {
      final ttsStopwatch = Stopwatch()..start();
      final wavBytes = await _voicevoxService.synthesize(
        cleanSentence,
        speakerId: _getSettings().voicevoxSpeakerId,
      );
      ttsStopwatch.stop();
      appLog('[Performance] TTS (Voicevox) latency for ${cleanSentence.length} chars: ${ttsStopwatch.elapsedMilliseconds}ms');

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

  String _getToolNotificationPhrase(String languageCode) {
    if (languageCode.startsWith('ja')) {
      return '調べてみますね'; // "Let me check that for you"
    } else if (languageCode.startsWith('zh')) {
      return '我来查一下';     // "I'll check it"
    } else if (languageCode.startsWith('ko')) {
      return '확인해 볼게요';   // "I'll look into it"
    } else {
      return 'Let me check that for you.';
    }
  }
}
