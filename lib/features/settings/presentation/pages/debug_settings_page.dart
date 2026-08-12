import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../providers/settings_notifier.dart';
import 'computer_use_debug_page.dart';

class DebugSettingsPage extends ConsumerWidget {
  const DebugSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_debug'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'settings.debug_section'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('settings.show_memory_updates'.tr()),
                  subtitle: Text('settings.show_memory_updates_desc'.tr()),
                  value: settings.showMemoryUpdates,
                  onChanged: notifier.updateShowMemoryUpdates,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text('settings.enable_llm_session_logs'.tr()),
                  subtitle: Text('settings.enable_llm_session_logs_desc'.tr()),
                  value: settings.enableLlmSessionLogs,
                  onChanged: notifier.updateEnableLlmSessionLogs,
                ),
                const Divider(height: 1),
                _FeedbackUploadSettings(settings: settings, notifier: notifier),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.desktop_mac_outlined),
                  title: const Text('Computer Use Smoke Sequence'),
                  subtitle: const Text(
                    'Run direct macOS permission, screenshot, window, input, and audio checks.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ComputerUseDebugPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackUploadSettings extends StatefulWidget {
  const _FeedbackUploadSettings({
    required this.settings,
    required this.notifier,
  });

  final AppSettings settings;
  final SettingsNotifier notifier;

  @override
  State<_FeedbackUploadSettings> createState() =>
      _FeedbackUploadSettingsState();
}

class _FeedbackUploadSettingsState extends State<_FeedbackUploadSettings> {
  late final TextEditingController _endpointController;
  late final TextEditingController _authTokenController;

  @override
  void initState() {
    super.initState();
    _endpointController = TextEditingController(
      text: widget.settings.feedbackEndpointUrl,
    );
    _authTokenController = TextEditingController(
      text: widget.settings.feedbackEndpointAuthToken,
    );
  }

  @override
  void didUpdateWidget(_FeedbackUploadSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_endpointController.text != widget.settings.feedbackEndpointUrl) {
      _endpointController.text = widget.settings.feedbackEndpointUrl;
    }
    if (_authTokenController.text !=
        widget.settings.feedbackEndpointAuthToken) {
      _authTokenController.text = widget.settings.feedbackEndpointAuthToken;
    }
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _authTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final notifier = widget.notifier;
    return Column(
      children: [
        SwitchListTile(
          title: Text('settings.feedback_upload_enabled'.tr()),
          subtitle: Text('settings.feedback_upload_enabled_desc'.tr()),
          value: settings.feedbackUploadEnabled,
          onChanged: notifier.updateFeedbackUploadEnabled,
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('feedback-endpoint-url-field'),
                  controller: _endpointController,
                  decoration: InputDecoration(
                    labelText: 'settings.feedback_endpoint_url'.tr(),
                    border: const OutlineInputBorder(),
                    helperText: 'settings.feedback_endpoint_url_helper'.tr(),
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: notifier.updateFeedbackEndpointUrl,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('feedback-endpoint-auth-token-field'),
                  controller: _authTokenController,
                  decoration: InputDecoration(
                    labelText: 'settings.feedback_endpoint_auth_token'.tr(),
                    border: const OutlineInputBorder(),
                    helperText: 'settings.feedback_endpoint_auth_token_helper'
                        .tr(),
                  ),
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: notifier.updateFeedbackEndpointAuthToken,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'settings.feedback_endpoint_credentials_helper'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: settings.feedbackUploadEnabled
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 160),
        ),
      ],
    );
  }
}
