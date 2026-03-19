import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../chat/data/repositories/chat_memory_repository.dart';
import '../../../chat/data/datasources/mcp_tool_service.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/services/session_memory_service.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../providers/model_list_provider.dart';
import '../providers/settings_notifier.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late SessionMemoryService _sessionMemoryService;
  late MemorySnapshot _memorySnapshot;
  late TextEditingController _baseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _maxTokensController;
  late TextEditingController _mcpUrlController;
  late TextEditingController _profilePersonaController;
  late TextEditingController _profilePreferencesController;
  late TextEditingController _profileDoNotController;
  late String _selectedModel;
  late double _temperature;
  late bool _mcpEnabled;
  late AssistantMode _assistantMode;
  // Voice settings
  late bool _ttsEnabled;
  late bool _autoReadEnabled;
  late double _speechRate;

  @override
  void initState() {
    super.initState();
    _sessionMemoryService = SessionMemoryService(
      ref.read(chatMemoryRepositoryProvider),
    );
    _memorySnapshot = _sessionMemoryService.loadSnapshot();
    final settings = ref.read(settingsNotifierProvider);
    final profile = _memorySnapshot.profile;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _maxTokensController = TextEditingController(
      text: settings.maxTokens.toString(),
    );
    _mcpUrlController = TextEditingController(text: settings.mcpUrl);
    _selectedModel = settings.model;
    _temperature = settings.temperature;
    _mcpEnabled = settings.mcpEnabled;
    _assistantMode = settings.assistantMode;
    _profilePersonaController = TextEditingController(
      text: profile.persona.join('\n'),
    );
    _profilePreferencesController = TextEditingController(
      text: profile.preferences.join('\n'),
    );
    _profileDoNotController = TextEditingController(
      text: profile.doNot.join('\n'),
    );
    // Voice settings
    _ttsEnabled = settings.ttsEnabled;
    _autoReadEnabled = settings.autoReadEnabled;
    _speechRate = settings.speechRate;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _maxTokensController.dispose();
    _mcpUrlController.dispose();
    _profilePersonaController.dispose();
    _profilePreferencesController.dispose();
    _profileDoNotController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final notifier = ref.read(settingsNotifierProvider.notifier);

    await notifier.updateBaseUrl(_baseUrlController.text.trim());
    await notifier.updateModel(_selectedModel.trim());
    await notifier.updateApiKey(_apiKeyController.text.trim());
    await notifier.updateMaxTokens(
      int.tryParse(_maxTokensController.text) ?? 4096,
    );
    await notifier.updateTemperature(_temperature);
    await notifier.updateMcpUrl(_mcpUrlController.text.trim());
    await notifier.updateMcpEnabled(_mcpEnabled);
    await notifier.updateAssistantMode(_assistantMode);
    // Voice settings
    await notifier.updateTtsEnabled(_ttsEnabled);
    await notifier.updateAutoReadEnabled(_autoReadEnabled);
    await notifier.updateSpeechRate(_speechRate);
    await _sessionMemoryService.saveProfileFromText(
      personaText: _profilePersonaController.text,
      preferencesText: _profilePreferencesController.text,
      doNotText: _profileDoNotController.text,
    );
    _reloadMemorySnapshot();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('settings.saved'.tr())));
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.reset_title'.tr()),
        content: Text('settings.reset_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.reset'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(settingsNotifierProvider.notifier).resetToDefaults();
      if (mounted) {
        setState(() {
          _baseUrlController.text = ApiConstants.defaultBaseUrl;
          _apiKeyController.text = ApiConstants.defaultApiKey;
          _maxTokensController.text = ApiConstants.defaultMaxTokens.toString();
          _selectedModel = ApiConstants.defaultModel;
          _temperature = ApiConstants.defaultTemperature;
          _assistantMode = AssistantMode.general;
          // Reset voice settings
          _ttsEnabled = true;
          _autoReadEnabled = false;
          _speechRate = 1.0;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('settings.reset_done'.tr())));
      }
    }
  }

  Future<void> _clearConversationMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('settings.clear_memory_title'.tr()),
        content: Text('settings.clear_memory_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _sessionMemoryService.clearAll();
    if (!mounted) return;

    setState(() {
      _profilePersonaController.clear();
      _profilePreferencesController.clear();
      _profileDoNotController.clear();
    });
    _reloadMemorySnapshot();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('settings.clear_memory_done'.tr())));
  }

  void _reloadMemorySnapshot() {
    if (!mounted) return;
    setState(() {
      _memorySnapshot = _sessionMemoryService.loadSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        actions: [
          IconButton(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restore),
            tooltip: 'settings.reset_to_default'.tr(),
          ),
        ],
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

          // Assistant settings section
          _buildSectionHeader('settings.assistant_section'.tr()),
          const SizedBox(height: 16),
          SegmentedButton<AssistantMode>(
            segments: const [
              ButtonSegment(
                value: AssistantMode.general,
                label: Text('General'),
                icon: Icon(Icons.chat_outlined),
              ),
              ButtonSegment(
                value: AssistantMode.coding,
                label: Text('Coding'),
                icon: Icon(Icons.code),
              ),
            ],
            selected: {_assistantMode},
            onSelectionChanged: (selection) {
              setState(() {
                _assistantMode = selection.first;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _assistantMode == AssistantMode.general
                ? 'settings.assistant_general_desc'.tr()
                : 'settings.assistant_coding_desc'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),

          // Conversation memory section
          Row(
            children: [
              _buildSectionHeader('settings.memory_section'.tr()),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _reloadMemorySnapshot,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'settings.memory_refresh'.tr(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'settings.memory_status'.tr(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'settings.profile_count'.tr(namedArgs: {
                      'count': '${_memorySnapshot.profile.persona.length + _memorySnapshot.profile.preferences.length + _memorySnapshot.profile.doNot.length}',
                    }),
                  ),
                  Text(
                    'settings.summary_count'.tr(namedArgs: {
                      'count': '${_memorySnapshot.summaryCount}',
                    }),
                  ),
                  Text(
                    'settings.memory_count'.tr(namedArgs: {
                      'count': '${_memorySnapshot.memoryCount}',
                    }),
                  ),
                  Text(
                    'settings.last_updated'.tr(namedArgs: {
                      'date': _formatDateTime(_memorySnapshot.lastUpdatedAt),
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profilePersonaController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'settings.profile_label'.tr(),
              hintText: 'settings.profile_hint'.tr(),
              border: const OutlineInputBorder(),
              helperText: 'settings.profile_helper'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profilePreferencesController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'settings.preferences_label'.tr(),
              hintText: 'settings.preferences_hint'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profileDoNotController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'settings.do_not_label'.tr(),
              hintText: 'settings.do_not_hint'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _clearConversationMemory,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text('settings.clear_memory'.tr()),
            ),
          ),
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

          // MCP settings section
          _buildSectionHeader('settings.mcp_section'.tr()),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('settings.mcp_enable'.tr()),
            subtitle: Text('settings.mcp_enable_desc'.tr()),
            value: _mcpEnabled,
            onChanged: (value) {
              setState(() {
                _mcpEnabled = value;
              });
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _mcpUrlController,
            enabled: _mcpEnabled,
            decoration: InputDecoration(
              labelText: 'MCP Server URL',
              hintText: 'http://localhost:8081',
              border: const OutlineInputBorder(),
              helperText: 'settings.mcp_url_helper'.tr(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          // Connection test button and tool list
          if (_mcpEnabled) _buildMcpToolsSection(),
          const SizedBox(height: 24),

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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'common.none'.tr();
    return '${value.year.toString().padLeft(4, '0')}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
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
            onChanged: null,
          ),
          const SizedBox(height: 8),
          Text(
            '${'settings.model_error_message'.tr()}\n$error',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpToolsSection() {
    final mcpToolService = ref.watch(mcpToolServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connection test button
        OutlinedButton.icon(
          onPressed: () async {
            if (mcpToolService == null) {
              appLog('[Settings] MCP connection test: mcpToolService is null');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('settings.mcp_service_null'.tr())),
              );
              return;
            }

            final testUrl = _mcpUrlController.text.trim();
            appLog('[Settings] MCP connection test started: URL=$testUrl');

            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('settings.mcp_testing'.tr())));

            await mcpToolService.connect(overrideUrl: testUrl);

            if (!mounted) return;

            final status = mcpToolService.status;
            final tools = mcpToolService.tools;

            appLog(
              '[Settings] MCP connection test result: status=$status, tools=${tools.length}, lastError=${mcpToolService.lastError}',
            );

            if (status == McpConnectionStatus.connected) {
              appLog(
                '[Settings] Connection succeeded: tools=${tools.map((t) => t.name).toList()}',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'settings.mcp_success'.tr(namedArgs: {'count': '${tools.length}'}),
                  ),
                ),
              );
              setState(() {}); // Refresh the tool list.
            } else {
              appLog('[Settings] Connection failed: ${mcpToolService.lastError}');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'settings.mcp_failed'.tr(namedArgs: {
                      'error': mcpToolService.lastError ?? 'common.unknown_error'.tr(),
                    }),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          },
          icon: const Icon(Icons.refresh),
          label: Text('settings.mcp_test_button'.tr()),
        ),
        const SizedBox(height: 12),
        // Tool list
        _buildToolsList(mcpToolService),
      ],
    );
  }

  Widget _buildToolsList(McpToolService? mcpToolService) {
    if (mcpToolService == null) {
      return Text(
        'settings.mcp_service_null'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    final status = mcpToolService.status;
    final tools = mcpToolService.tools;

    if (status == McpConnectionStatus.disconnected) {
      return Text(
        'settings.mcp_disconnected'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    if (status == McpConnectionStatus.connecting) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('settings.mcp_connecting'.tr()),
        ],
      );
    }

    if (status == McpConnectionStatus.error) {
      return Text(
        'settings.mcp_error'.tr(namedArgs: {
          'error': mcpToolService.lastError ?? 'common.unknown'.tr(),
        }),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    if (tools.isEmpty) {
      return Text(
        'settings.mcp_no_tools'.tr(),
        style: const TextStyle(color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'settings.mcp_available_tools'.tr(namedArgs: {'count': '${tools.length}'}),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        ...tools.map(
          (tool) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.build_outlined),
              title: Text(tool.name),
              subtitle: Text(
                tool.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              dense: true,
            ),
          ),
        ),
      ],
    );
  }
}
