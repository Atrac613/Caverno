import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../utils/logger.dart';

/// Microphone recorder with voice activity detection (VAD).
///
/// Uses the `record` package to stream PCM16 data from the microphone,
/// monitors volume to detect speech start/end, and produces a WAV file.
class VoiceRecorder {
  VoiceRecorder();

  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Uint8List>? _streamSubscription;

  /// Accumulated PCM16 samples during recording.
  final List<int> _pcmBuffer = [];

  bool _isRecording = false;

  /// Whether speech has been detected during the current recording session.
  bool _speechDetected = false;

  /// Timer used to detect end-of-speech silence.
  Timer? _silenceTimer;

  /// Callbacks.
  void Function(Uint8List wavBytes)? onSpeechEnd;
  void Function()? onSpeechDetected;
  void Function(double amplitude)? onAmplitudeChanged;

  /// Volume threshold below which we consider silence (RMS amplitude 0..1).
  static const double _silenceThreshold = 0.02;

  /// Duration of silence required to finalize speech.
  static const Duration _silenceDuration = Duration(milliseconds: 1200);

  /// Sample rate used for recording.
  static const int _sampleRate = 16000;

  bool get isRecording => _isRecording;

  /// Start recording and listening for speech.
  ///
  /// Once speech is detected and then followed by silence, [onSpeechEnd]
  /// is called with the captured WAV bytes.
  /// Returns `false` if microphone permission was denied.
  Future<bool> startRecording() async {
    if (_isRecording) return true;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      appLog('[VoiceRecorder] Microphone permission denied');
      return false;
    }

    _pcmBuffer.clear();
    _speechDetected = false;
    _isRecording = true;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    appLog('[VoiceRecorder] Recording started');

    _streamSubscription = stream.listen(
      (chunk) {
        _pcmBuffer.addAll(chunk);
        final rms = _calculateRms(chunk);
        onAmplitudeChanged?.call(rms);

        if (rms > _silenceThreshold) {
          // Speech detected.
          if (!_speechDetected) {
            _speechDetected = true;
            appLog('[VoiceRecorder] Speech detected');
            onSpeechDetected?.call();
          }
          _silenceTimer?.cancel();
          _silenceTimer = null;
        } else if (_speechDetected && _silenceTimer == null) {
          // Start silence timer after speech was detected.
          _silenceTimer = Timer(_silenceDuration, () {
            appLog('[VoiceRecorder] Silence detected — finalizing');
            _finalizeRecording();
          });
        }
      },
      onError: (error) {
        appLog('[VoiceRecorder] Stream error: $error');
        stopRecording();
      },
    );

    return true;
  }

  /// Start monitoring microphone volume without recording.
  /// Used for barge-in detection during TTS playback.
  /// Returns `false` if microphone permission was denied.
  Future<bool> startMonitoring() async {
    if (_isRecording) return true;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    _isRecording = true;
    _speechDetected = false;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    appLog('[VoiceRecorder] Monitoring started');

    _streamSubscription = stream.listen(
      (chunk) {
        final rms = _calculateRms(chunk);
        onAmplitudeChanged?.call(rms);
        if (rms > _silenceThreshold && !_speechDetected) {
          _speechDetected = true;
          appLog('[VoiceRecorder] Barge-in speech detected');
          onSpeechDetected?.call();
        }
      },
      onError: (error) {
        appLog('[VoiceRecorder] Monitor stream error: $error');
      },
    );

    return true;
  }

  /// Stop recording / monitoring without producing output.
  Future<void> stopRecording() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    if (_isRecording) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    _isRecording = false;
    _pcmBuffer.clear();
    _speechDetected = false;
  }

  /// Finalize and deliver the recorded WAV.
  Future<void> _finalizeRecording() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _isRecording = false;

    if (_pcmBuffer.isEmpty) {
      _pcmBuffer.clear();
      return;
    }

    final wavBytes = _buildWav(_pcmBuffer, _sampleRate);
    _pcmBuffer.clear();
    _speechDetected = false;

    appLog('[VoiceRecorder] WAV produced: ${wavBytes.length} bytes');
    onSpeechEnd?.call(wavBytes);
  }

  /// Release resources.
  Future<void> dispose() async {
    await stopRecording();
    _recorder.dispose();
  }

  /// Calculate RMS volume from PCM16 bytes.
  double _calculateRms(Uint8List pcmBytes) {
    if (pcmBytes.length < 2) return 0.0;

    final byteData = ByteData.sublistView(pcmBytes);
    final sampleCount = pcmBytes.length ~/ 2;
    double sumSquares = 0;

    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
    }

    return sqrt(sumSquares / sampleCount);
  }

  /// Build a WAV file from PCM16 samples.
  static Uint8List _buildWav(List<int> pcmBytes, int sampleRate) {
    final dataLength = pcmBytes.length;
    final fileLength = 44 + dataLength;
    final byteData = ByteData(fileLength);

    // RIFF header.
    byteData.setUint8(0, 0x52); // R
    byteData.setUint8(1, 0x49); // I
    byteData.setUint8(2, 0x46); // F
    byteData.setUint8(3, 0x46); // F
    byteData.setUint32(4, fileLength - 8, Endian.little);
    byteData.setUint8(8, 0x57); // W
    byteData.setUint8(9, 0x41); // A
    byteData.setUint8(10, 0x56); // V
    byteData.setUint8(11, 0x45); // E

    // fmt sub-chunk.
    byteData.setUint8(12, 0x66); // f
    byteData.setUint8(13, 0x6D); // m
    byteData.setUint8(14, 0x74); // t
    byteData.setUint8(15, 0x20); // (space)
    byteData.setUint32(16, 16, Endian.little); // Sub-chunk size.
    byteData.setUint16(20, 1, Endian.little); // PCM format.
    byteData.setUint16(22, 1, Endian.little); // Mono.
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // Byte rate.
    byteData.setUint16(32, 2, Endian.little); // Block align.
    byteData.setUint16(34, 16, Endian.little); // Bits per sample.

    // data sub-chunk.
    byteData.setUint8(36, 0x64); // d
    byteData.setUint8(37, 0x61); // a
    byteData.setUint8(38, 0x74); // t
    byteData.setUint8(39, 0x61); // a
    byteData.setUint32(40, dataLength, Endian.little);

    // PCM data.
    for (var i = 0; i < dataLength; i++) {
      byteData.setUint8(44 + i, pcmBytes[i]);
    }

    return byteData.buffer.asUint8List();
  }
}
