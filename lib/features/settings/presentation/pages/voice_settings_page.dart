import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/voicevox_audio_player.dart';
import '../../../../core/services/voicevox_service.dart';
import '../providers/settings_notifier.dart';

class VoiceSettingsPage extends ConsumerStatefulWidget {
  const VoiceSettingsPage({super.key});

  @override
  ConsumerState<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends ConsumerState<VoiceSettingsPage> {
  late bool _ttsEnabled;
  late bool _autoReadEnabled;
  late double _speechRate;
  late bool _voiceModeAutoStop;
  late String _whisperUrl;
  late String _voicevoxUrl;
  late int _voicevoxSpeakerId;

  VoicevoxAudioPlayer? _voicevoxAudioPlayer;
  bool _isPlayingPreview = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _ttsEnabled = settings.ttsEnabled;
    _autoReadEnabled = settings.autoReadEnabled;
    _speechRate = settings.speechRate;
    _voiceModeAutoStop = settings.voiceModeAutoStop;
    _whisperUrl = settings.whisperUrl;
    _voicevoxUrl = settings.voicevoxUrl;
    _voicevoxSpeakerId = settings.voicevoxSpeakerId;
  }

  @override
  void dispose() {
    _voicevoxAudioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final notifier = ref.read(settingsNotifierProvider.notifier);
    await notifier.updateTtsEnabled(_ttsEnabled);
    await notifier.updateAutoReadEnabled(_autoReadEnabled);
    await notifier.updateSpeechRate(_speechRate);
    await notifier.updateVoiceModeAutoStop(_voiceModeAutoStop);
    await notifier.updateWhisperUrl(_whisperUrl);
    await notifier.updateVoicevoxUrl(_voicevoxUrl);
    await notifier.updateVoicevoxSpeakerId(_voicevoxSpeakerId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('settings.saved'.tr())));
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectSpeaker() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final speakers = await VoicevoxService(baseUrl: _voicevoxUrl).getSpeakers();
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
                  selected: _voicevoxSpeakerId == spk.speakerId,
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
        setState(() {
          _voicevoxSpeakerId = selected;
        });
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
      final bytes = await VoicevoxService(baseUrl: _voicevoxUrl)
          .synthesize('settings.voicevox_preview_text'.tr(), speakerId: _voicevoxSpeakerId);
      
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
            value: _ttsEnabled,
            onChanged: (value) {
              setState(() {
                _ttsEnabled = value;
                if (!value) {
                  _autoReadEnabled = false;
                }
              });
            },
          ),
          SwitchListTile(
            title: Text('settings.auto_read'.tr()),
            subtitle: Text('settings.auto_read_desc'.tr()),
            value: _autoReadEnabled,
            onChanged: _ttsEnabled
                ? (value) {
                    setState(() {
                      _autoReadEnabled = value;
                    });
                  }
                : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('settings.speech_rate'.tr()),
              Expanded(
                child: Slider(
                  value: _speechRate,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  label: '${_speechRate.toStringAsFixed(1)}x',
                  onChanged: _ttsEnabled
                      ? (value) {
                          setState(() {
                            _speechRate = value;
                          });
                        }
                      : null,
                ),
              ),
              SizedBox(
                width: 50,
                child: Text('${_speechRate.toStringAsFixed(1)}x'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('settings.voice_mode_auto_stop'.tr()),
            subtitle: Text('settings.voice_mode_auto_stop_desc'.tr()),
            value: _voiceModeAutoStop,
            onChanged: (value) {
              setState(() {
                _voiceModeAutoStop = value;
              });
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _whisperUrl,
            decoration: InputDecoration(
              labelText: 'settings.whisper_url'.tr(),
              hintText: 'http://localhost:8080',
              border: const OutlineInputBorder(),
              helperText: 'settings.whisper_url_helper'.tr(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (value) {
              setState(() {
                _whisperUrl = value;
              });
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: _voicevoxUrl,
            decoration: InputDecoration(
              labelText: 'settings.voicevox_url'.tr(),
              hintText: 'http://localhost:50021',
              border: const OutlineInputBorder(),
              helperText: 'settings.voicevox_url_helper'.tr(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (value) {
              setState(() {
                _voicevoxUrl = value;
              });
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            title: Text('settings.voicevox_speaker_id'.tr()),
            subtitle: Text('Speaker ID: $_voicevoxSpeakerId'),
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
          const SizedBox(height: 24),

          // Save button
          FilledButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: Text('settings.save_settings'.tr()),
          ),
        ],
      ),
    );
  }
}
