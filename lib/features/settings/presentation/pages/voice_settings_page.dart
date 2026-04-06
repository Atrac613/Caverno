import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/voicevox_audio_player.dart';
import '../../../../core/services/voicevox_service.dart';
import '../../../../core/utils/debouncer.dart';
import '../providers/settings_notifier.dart';

class VoiceSettingsPage extends ConsumerStatefulWidget {
  const VoiceSettingsPage({super.key});

  @override
  ConsumerState<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends ConsumerState<VoiceSettingsPage> {
  VoicevoxAudioPlayer? _voicevoxAudioPlayer;
  bool _isPlayingPreview = false;

  final _whisperUrlDebouncer = Debouncer();
  final _voicevoxUrlDebouncer = Debouncer();

  @override
  void dispose() {
    _whisperUrlDebouncer.dispose();
    _voicevoxUrlDebouncer.dispose();
    _voicevoxAudioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _selectSpeaker() async {
    final settings = ref.read(settingsNotifierProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final speakers = await VoicevoxService(baseUrl: settings.voicevoxUrl).getSpeakers();
      if (!mounted) return;
      Navigator.pop(context); // close loading

      final selected = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('settings.voicevox_speaker_id'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: speakers.length,
              itemBuilder: (context, index) {
                final spk = speakers[index];
                return ListTile(
                  title: Text(spk.displayName),
                  selected: settings.voicevoxSpeakerId == spk.speakerId,
                  onTap: () => Navigator.pop(context, spk.speakerId),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
          ],
        ),
      );
      if (selected != null) {
        ref.read(settingsNotifierProvider.notifier).updateVoicevoxSpeakerId(selected);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _previewVoicevox() async {
    setState(() {
      _isPlayingPreview = true;
    });
    try {
      final s = ref.read(settingsNotifierProvider);
      final bytes = await VoicevoxService(baseUrl: s.voicevoxUrl)
          .synthesize('settings.voicevox_preview_text'.tr(), speakerId: s.voicevoxSpeakerId);
      
      _voicevoxAudioPlayer ??= VoicevoxAudioPlayer();
      _voicevoxAudioPlayer!.onQueueComplete = () {
        if (mounted) {
          setState(() {
            _isPlayingPreview = false;
          });
        }
      };
      _voicevoxAudioPlayer!.enqueue(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play preview: $e')),
        );
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.menu_voice'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Voice settings section
          _buildSectionHeader('settings.voice_section'.tr()),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('settings.tts'.tr()),
            subtitle: Text('settings.tts_desc'.tr()),
            value: settings.ttsEnabled,
            onChanged: (value) {
              notifier.updateTtsEnabled(value);
              if (!value) {
                notifier.updateAutoReadEnabled(false);
              }
            },
          ),
          SwitchListTile(
            title: Text('settings.auto_read'.tr()),
            subtitle: Text('settings.auto_read_desc'.tr()),
            value: settings.autoReadEnabled,
            onChanged: settings.ttsEnabled
                ? (value) => notifier.updateAutoReadEnabled(value)
                : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('settings.speech_rate'.tr()),
              Expanded(
                child: Slider(
                  value: settings.speechRate,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(settings.speechRate * 2).toStringAsFixed(1)}x',
                  onChanged: settings.ttsEnabled
                      ? (value) => notifier.updateSpeechRate(value)
                      : null,
                ),
              ),
              SizedBox(
                width: 50,
                child: Text('${(settings.speechRate * 2).toStringAsFixed(1)}x'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('settings.voice_mode_auto_stop'.tr()),
            subtitle: Text('settings.voice_mode_auto_stop_desc'.tr()),
            value: settings.voiceModeAutoStop,
            onChanged: (value) => notifier.updateVoiceModeAutoStop(value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: settings.whisperUrl,
            decoration: InputDecoration(
              labelText: 'settings.whisper_url'.tr(),
              hintText: 'http://localhost:8080',
              border: const OutlineInputBorder(),
              helperText: 'settings.whisper_url_helper'.tr(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (value) {
              _whisperUrlDebouncer.run(() {
                notifier.updateWhisperUrl(value.trim());
              });
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: settings.voicevoxUrl,
            decoration: InputDecoration(
              labelText: 'settings.voicevox_url'.tr(),
              hintText: 'http://localhost:50021',
              border: const OutlineInputBorder(),
              helperText: 'settings.voicevox_url_helper'.tr(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (value) {
              _voicevoxUrlDebouncer.run(() {
                notifier.updateVoicevoxUrl(value.trim());
              });
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            title: Text('settings.voicevox_speaker_id'.tr()),
            subtitle: Text('Speaker ID: ${settings.voicevoxSpeakerId}'),
            trailing: const Icon(Icons.arrow_drop_down),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            onTap: _selectSpeaker,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isPlayingPreview ? null : _previewVoicevox,
              icon: _isPlayingPreview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text('settings.voicevox_preview'.tr()),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
