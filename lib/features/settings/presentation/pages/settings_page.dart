import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
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
      ).showSnackBar(const SnackBar(content: Text('設定を保存しました')));
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定をリセット'),
        content: const Text('すべての設定をデフォルト値に戻しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('リセット'),
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
        ).showSnackBar(const SnackBar(content: Text('設定をリセットしました')));
      }
    }
  }

  Future<void> _clearConversationMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('会話メモリを削除'),
        content: const Text('プロフィール・要約・記憶をすべて削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
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
    ).showSnackBar(const SnackBar(content: Text('会話メモリを削除しました')));
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
        title: const Text('接続設定'),
        actions: [
          IconButton(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restore),
            tooltip: 'デフォルトに戻す',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server settings section
          _buildSectionHeader('サーバー設定'),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'http://localhost:1234/v1',
              border: OutlineInputBorder(),
              helperText: 'LM Studio などの OpenAI 互換APIエンドポイント',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'no-key',
              border: OutlineInputBorder(),
              helperText: 'ローカルLLMでは通常不要',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),

          // Model settings section
          Row(
            children: [
              _buildSectionHeader('モデル設定'),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'モデル一覧を再取得',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildModelSelector(),
          const SizedBox(height: 24),

          // Assistant settings section
          _buildSectionHeader('アシスタント設定'),
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
                ? '汎用アシスタントとして応答します'
                : '技術タスクでは、より厳密なエンジニア寄りの応答をします',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),

          // Conversation memory section
          Row(
            children: [
              _buildSectionHeader('会話メモリ'),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _reloadMemorySnapshot,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'メモリ状態を更新',
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
                  Text('保存状況', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    'プロフィール: ${_memorySnapshot.profile.persona.length + _memorySnapshot.profile.preferences.length + _memorySnapshot.profile.doNot.length}件',
                  ),
                  Text('セッション要約: ${_memorySnapshot.summaryCount}件'),
                  Text('関連記憶: ${_memorySnapshot.memoryCount}件'),
                  Text(
                    '最終更新: ${_formatDateTime(_memorySnapshot.lastUpdatedAt)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profilePersonaController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'ユーザープロフィール (1行1項目)',
              hintText: '例: Flutterエンジニア',
              border: OutlineInputBorder(),
              helperText: '新規セッション開始時に優先して参照',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profilePreferencesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '回答の好み (1行1項目)',
              hintText: '例: 結論先出し / 箇条書き / 実装例重視',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _profileDoNotController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '避けたいこと (1行1項目)',
              hintText: '例: 長い前置き / 抽象論のみ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _clearConversationMemory,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('会話メモリを全削除'),
            ),
          ),
          const SizedBox(height: 24),

          // Generation parameters section
          _buildSectionHeader('生成パラメータ'),
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
            decoration: const InputDecoration(
              labelText: 'Max Tokens',
              hintText: '4096',
              border: OutlineInputBorder(),
              helperText: '生成する最大トークン数',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),

          // MCP settings section
          _buildSectionHeader('MCP (ツール)'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('MCPツールを有効化'),
            subtitle: const Text('LLMがWeb検索などのツールを使用可能に'),
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
            decoration: const InputDecoration(
              labelText: 'MCP Server URL',
              hintText: 'http://localhost:8081',
              border: OutlineInputBorder(),
              helperText: 'SearXNG等のMCPサーバーURL',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          // Connection test button and tool list
          if (_mcpEnabled) _buildMcpToolsSection(),
          const SizedBox(height: 24),

          // Voice settings section
          _buildSectionHeader('音声設定'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('音声読み上げ'),
            subtitle: const Text('アシスタントの応答を読み上げ'),
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
            title: const Text('自動読み上げ'),
            subtitle: const Text('新しい応答を自動で読み上げ'),
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
              const Text('読み上げ速度: '),
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
            label: const Text('設定を保存'),
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
    if (value == null) return 'なし';
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
          decoration: const InputDecoration(
            labelText: 'モデル名',
            border: OutlineInputBorder(),
            helperText: 'APIの /models から取得した一覧',
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
        decoration: const InputDecoration(
          labelText: 'モデル名',
          border: OutlineInputBorder(),
          helperText: 'モデル一覧を取得中',
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('利用可能なモデルを読み込んでいます...')),
          ],
        ),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedModel,
            decoration: const InputDecoration(
              labelText: 'モデル名',
              border: OutlineInputBorder(),
              helperText: 'モデル一覧を取得できないため現在値を表示しています',
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
            'モデル一覧の取得に失敗しました。Base URL / API Key を確認して再読み込みしてください。\n$error',
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
              print('[Settings] MCP接続テスト: mcpToolService is null');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('MCPサービスが初期化されていません')),
              );
              return;
            }

            final testUrl = _mcpUrlController.text.trim();
            print('[Settings] MCP接続テスト開始: URL=$testUrl');

            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('接続テスト中...')));

            await mcpToolService.connect(overrideUrl: testUrl);

            if (!mounted) return;

            final status = mcpToolService.status;
            final tools = mcpToolService.tools;

            print(
              '[Settings] MCP接続テスト結果: status=$status, tools=${tools.length}, lastError=${mcpToolService.lastError}',
            );

            if (status == McpConnectionStatus.connected) {
              print(
                '[Settings] 接続成功: ツール一覧=${tools.map((t) => t.name).toList()}',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('接続成功: ${tools.length}ツール取得')),
              );
              setState(() {}); // Refresh the tool list.
            } else {
              print('[Settings] 接続失敗: ${mcpToolService.lastError}');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '接続失敗: ${mcpToolService.lastError ?? "不明なエラー"}',
                  ),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          },
          icon: const Icon(Icons.refresh),
          label: const Text('接続テスト'),
        ),
        const SizedBox(height: 12),
        // Tool list
        _buildToolsList(mcpToolService),
      ],
    );
  }

  Widget _buildToolsList(McpToolService? mcpToolService) {
    if (mcpToolService == null) {
      return const Text(
        'MCPサービスが初期化されていません',
        style: TextStyle(color: Colors.grey),
      );
    }

    final status = mcpToolService.status;
    final tools = mcpToolService.tools;

    if (status == McpConnectionStatus.disconnected) {
      return const Text(
        '未接続（接続テストを実行してください）',
        style: TextStyle(color: Colors.grey),
      );
    }

    if (status == McpConnectionStatus.connecting) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('接続中...'),
        ],
      );
    }

    if (status == McpConnectionStatus.error) {
      return Text(
        'エラー: ${mcpToolService.lastError ?? "不明"}',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    if (tools.isEmpty) {
      return const Text(
        '利用可能なツールがありません（SearXNGフォールバック使用）',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '利用可能なツール (${tools.length}):',
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
