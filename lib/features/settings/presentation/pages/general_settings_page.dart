import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
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
  late String _selectedModel;
  late double _temperature;
  late String _language;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _maxTokensController = TextEditingController(text: settings.maxTokens.toString());
    _selectedModel = settings.model;
    _temperature = settings.temperature;
    _language = settings.language;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final notifier = ref.read(settingsNotifierProvider.notifier);
    await notifier.updateBaseUrl(_baseUrlController.text.trim());
    await notifier.updateModel(_selectedModel.trim());
    await notifier.updateApiKey(_apiKeyController.text.trim());
    await notifier.updateMaxTokens(int.tryParse(_maxTokensController.text) ?? 4096);
    await notifier.updateTemperature(_temperature);
    await notifier.updateLanguage(_language);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('settings.saved'.tr())));
      Navigator.of(context).pop();
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

  Widget _buildModelSelector() {
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
        if (!options.contains(_selectedModel)) {
          options.insert(0, _selectedModel);
        }

        return DropdownButtonFormField<String>(
          initialValue: _selectedModel,
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
            setState(() {
              _selectedModel = value;
            });
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
            initialValue: _selectedModel,
            decoration: InputDecoration(
              labelText: 'settings.model_name'.tr(),
              border: const OutlineInputBorder(),
              helperText: 'settings.model_error_helper'.tr(),
            ),
            items: [
              DropdownMenuItem<String>(
                value: _selectedModel,
                child: Text(_selectedModel, overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedModel = value;
              });
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
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.menu_general'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                  value: _temperature,
                  min: 0.0,
                  max: 2.0,
                  divisions: 20,
                  label: _temperature.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _temperature = value;
                    });
                  },
                ),
              ),
              SizedBox(width: 40, child: Text(_temperature.toStringAsFixed(1))),
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
          ),
          const SizedBox(height: 24),

          // Language section
          _buildSectionHeader('settings.language_section'.tr()),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
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
                setState(() {
                  _language = value;
                });
              }
            },
          ),
          const SizedBox(height: 32),

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
