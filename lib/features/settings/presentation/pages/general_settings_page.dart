import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/debouncer.dart';
import '../providers/model_list_provider.dart';
import '../providers/settings_notifier.dart';

class GeneralSettingsPage extends ConsumerStatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  ConsumerState<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends ConsumerState<GeneralSettingsPage> {
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _maxTokensController;

  final _baseUrlDebouncer = Debouncer();
  final _apiKeyDebouncer = Debouncer();
  final _maxTokensDebouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _maxTokensController = TextEditingController(text: settings.maxTokens.toString());
  }

  @override
  void dispose() {
    _baseUrlDebouncer.dispose();
    _apiKeyDebouncer.dispose();
    _maxTokensDebouncer.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _maxTokensController.dispose();
    super.dispose();
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

  Widget _buildModelSelector() {
    final settings = ref.watch(settingsNotifierProvider);
    final selectedModel = settings.model;
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final asyncModels = ref.watch(
      modelListProvider((
        baseUrl: baseUrl.isEmpty ? ApiConstants.defaultBaseUrl : baseUrl,
        apiKey: apiKey.isEmpty ? ApiConstants.defaultApiKey : apiKey,
      )),
    );

    return asyncModels.when(
      data: (models) {
        final options = [...models];
        if (!options.contains(selectedModel)) {
          options.insert(0, selectedModel);
        }

        return DropdownButtonFormField<String>(
          initialValue: selectedModel,
          decoration: InputDecoration(
            labelText: 'settings.model_name'.tr(),
            border: const OutlineInputBorder(),
            helperText: 'settings.model_list_helper'.tr(),
          ),
          items: options
              .map(
                (model) => DropdownMenuItem<String>(
                  value: model,
                  child: Text(model, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            ref.read(settingsNotifierProvider.notifier).updateModel(value.trim());
          },
        );
      },
      loading: () => InputDecorator(
        decoration: InputDecoration(
          labelText: 'settings.model_name'.tr(),
          border: const OutlineInputBorder(),
          helperText: 'settings.model_loading'.tr(),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('settings.model_loading_message'.tr())),
          ],
        ),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: selectedModel,
            decoration: InputDecoration(
              labelText: 'settings.model_name'.tr(),
              border: const OutlineInputBorder(),
              helperText: 'settings.model_error_helper'.tr(),
            ),
            items: [
              DropdownMenuItem<String>(
                value: selectedModel,
                child: Text(selectedModel, overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              ref.read(settingsNotifierProvider.notifier).updateModel(value.trim());
            },
          ),
          const SizedBox(height: 8),
          Text(
            'settings.model_error_message'.tr(),
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.menu_general'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Demo mode toggle
          SwitchListTile(
            title: Text('settings.demo_mode'.tr()),
            subtitle: Text('settings.demo_mode_desc'.tr()),
            value: settings.demoMode,
            onChanged: (value) => notifier.updateDemoMode(value),
          ),
          const Divider(),
          const SizedBox(height: 8),
          // Server, model, and generation settings (disabled in demo mode)
          IgnorePointer(
            ignoring: settings.demoMode,
            child: AnimatedOpacity(
              opacity: settings.demoMode ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server settings section
                  _buildSectionHeader('settings.server_section'.tr()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'http://localhost:1234/v1',
                      border: const OutlineInputBorder(),
                      helperText: 'settings.base_url_helper'.tr(),
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (_) {
                      _baseUrlDebouncer.run(() {
                        notifier.updateBaseUrl(_baseUrlController.text.trim());
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'no-key',
                      border: const OutlineInputBorder(),
                      helperText: 'settings.api_key_helper'.tr(),
                    ),
                    obscureText: true,
                    onChanged: (_) {
                      _apiKeyDebouncer.run(() {
                        notifier.updateApiKey(_apiKeyController.text.trim());
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Model settings section
                  Row(
                    children: [
                      _buildSectionHeader('settings.model_section'.tr()),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {});
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'settings.model_refresh'.tr(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildModelSelector(),
                  const SizedBox(height: 24),

                  // Generation parameters section
                  _buildSectionHeader('settings.generation_section'.tr()),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Temperature: '),
                      Expanded(
                        child: Slider(
                          value: settings.temperature,
                          min: 0.0,
                          max: 2.0,
                          divisions: 20,
                          label: settings.temperature.toStringAsFixed(1),
                          onChanged: (value) {
                            notifier.updateTemperature(value);
                          },
                        ),
                      ),
                      SizedBox(width: 40, child: Text(settings.temperature.toStringAsFixed(1))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _maxTokensController,
                    decoration: InputDecoration(
                      labelText: 'Max Tokens',
                      hintText: '4096',
                      border: const OutlineInputBorder(),
                      helperText: 'settings.max_tokens_helper'.tr(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      _maxTokensDebouncer.run(() {
                        final value = int.tryParse(_maxTokensController.text) ?? 4096;
                        notifier.updateMaxTokens(value);
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Language section
          _buildSectionHeader('settings.language_section'.tr()),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: settings.language,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: 'settings.language_helper'.tr(),
            ),
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text('settings.language_system'.tr()),
              ),
              DropdownMenuItem(
                value: 'ja',
                child: Text('settings.language_ja'.tr()),
              ),
              DropdownMenuItem(
                value: 'en',
                child: Text('settings.language_en'.tr()),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                notifier.updateLanguage(value);
              }
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
