import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';

import '../providers/voice_mode_notifier.dart';

/// Full-screen overlay for the Voice Mode conversation.
/// Shows animated visual feedback based on the current state (idle, listening, processing, speaking).
class VoiceModeOverlay extends ConsumerStatefulWidget {
  const VoiceModeOverlay({super.key});

  @override
  ConsumerState<VoiceModeOverlay> createState() => _VoiceModeOverlayState();
}

class _VoiceModeOverlayState extends ConsumerState<VoiceModeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(voiceModeNotifierProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _onStopPressed() {
    ref.read(voiceModeNotifierProvider.notifier).stop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceModeNotifierProvider);

    return PopScope(
      canPop: false, // Prevent back button from closing it immediately
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onStopPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.black.withAlpha(230),
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: _onStopPressed,
                      iconSize: 32,
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Central Animation Area
              SizedBox(
                height: 200,
                child: Center(
                  child: _buildAnimation(state.status),
                ),
              ),

              const SizedBox(height: 48),

              // Status Text
              Text(
                _getStatusText(state.status),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 16),

              // Error or Transcript Text
              if (state.status == VoiceModeStatus.error)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    state.errorMessage ?? 'Unknown error',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              else if (state.transcript.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    state.transcript,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.fade,
                  ),
                ),

              const Spacer(flex: 3),

              // Stop Button (Barge-in / Cancel)
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: FloatingActionButton.large(
                  onPressed: _onStopPressed,
                  backgroundColor: Colors.white24,
                  elevation: 0,
                  child: const Icon(Icons.stop_rounded, color: Colors.white, size: 40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusText(VoiceModeStatus status) {
    switch (status) {
      case VoiceModeStatus.idle:
        return '';
      case VoiceModeStatus.listening:
        return 'message.listening'.tr();
      case VoiceModeStatus.processing:
        return 'content.thinking_active'.tr();
      case VoiceModeStatus.speaking:
        return 'message.tts_play'.tr(); // E.g. "Speaking..." / "読み上げ中..."
      case VoiceModeStatus.error:
        return 'message.error'.tr();
    }
  }

  Widget _buildAnimation(VoiceModeStatus status) {
    switch (status) {
      case VoiceModeStatus.idle:
      case VoiceModeStatus.error:
        return GestureDetector(
          onTap: () {
            ref.read(voiceModeNotifierProvider.notifier).start();
          },
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_off, color: Colors.white54, size: 40),
          ),
        );

      case VoiceModeStatus.listening:
        final notifier = ref.read(voiceModeNotifierProvider.notifier);
        return ValueListenableBuilder<double>(
          valueListenable: notifier.audioLevel,
          builder: (context, level, child) {
            final visualBoost = (level * 20).clamp(0.0, 1.0);
            return AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final pulseSize = 100 + (_pulseController.value * 40);
                final totalSize = pulseSize + (visualBoost * 120);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: totalSize,
                  height: totalSize,
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(
                      (100 - (_pulseController.value * 60) + (visualBoost * 80)).clamp(0, 255).toInt(),
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 80 + (visualBoost * 20),
                      height: 80 + (visualBoost * 20),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 40 + (visualBoost * 10),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );

      case VoiceModeStatus.processing:
        return const SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            strokeWidth: 4,
          ),
        );

      case VoiceModeStatus.speaking:
        return AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return _buildWaveBar(index, _waveController.value);
              }),
            );
          },
        );
    }
  }

  Widget _buildWaveBar(int index, double animationValue) {
    // Generate a pseudo-random looking wave based on index and animation time
    final offset = index * 0.5;
    final wave = math.sin(animationValue * math.pi * 2 + offset);
    final height = 40 + (wave * 30).abs();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: 12,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
