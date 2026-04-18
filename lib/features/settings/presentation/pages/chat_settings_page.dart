import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../../../core/utils/debouncer.dart';
import '../../../chat/data/repositories/chat_memory_repository.dart';
import '../../../chat/domain/entities/session_memory.dart';
import '../../../chat/domain/services/session_memory_service.dart';
import '../providers/settings_notifier.dart';

class ChatSettingsPage extends ConsumerStatefulWidget {
  const ChatSettingsPage({super.key});

  @override
  ConsumerState<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends ConsumerState<ChatSettingsPage> {
  late SessionMemoryService _sessionMemoryService;
  late MemorySnapshot _memorySnapshot;
  late List<MemoryEntry> _storedMemories;
  late List<MemoryReviewItem> _reviewQueue;
  late List<MemorySessionSummary> _sessionSummaries;
  late TextEditingController _profilePersonaController;
  late TextEditingController _profilePreferencesController;
  late TextEditingController _profileDoNotController;

  final _profileDebouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    _sessionMemoryService = SessionMemoryService(
      ref.read(chatMemoryRepositoryProvider),
    );
    _memorySnapshot = _sessionMemoryService.loadSnapshot();
    _storedMemories = _sessionMemoryService.loadMemories();
    _reviewQueue = _sessionMemoryService.loadReviewQueue();
    _sessionSummaries = _sessionMemoryService.loadSessionSummaries();
    final profile = _memorySnapshot.profile;

    _profilePersonaController = TextEditingController(
      text: profile.persona.join('\n'),
    );
    _profilePreferencesController = TextEditingController(
      text: profile.preferences.join('\n'),
    );
    _profileDoNotController = TextEditingController(
      text: profile.doNot.join('\n'),
    );
  }

  @override
  void dispose() {
    _profileDebouncer.dispose();
    _profilePersonaController.dispose();
    _profilePreferencesController.dispose();
    _profileDoNotController.dispose();
    super.dispose();
  }

  void _autoSaveProfile() {
    _profileDebouncer.run(() async {
      await _sessionMemoryService.saveProfileFromText(
        personaText: _profilePersonaController.text,
        preferencesText: _profilePreferencesController.text,
        doNotText: _profileDoNotController.text,
      );
      _reloadMemorySnapshot();
    });
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
      _storedMemories = _sessionMemoryService.loadMemories();
      _reviewQueue = _sessionMemoryService.loadReviewQueue();
      _sessionSummaries = _sessionMemoryService.loadSessionSummaries();
    });
  }

  Future<void> _keepMemoryReview(String id) async {
    await _sessionMemoryService.keepReviewItem(id);
    _reloadMemorySnapshot();
  }

  Future<void> _deleteMemoryReview(String id) async {
    await _sessionMemoryService.deleteReviewItem(id);
    _reloadMemorySnapshot();
  }

  Future<void> _suppressMemoryReview(String id) async {
    await _sessionMemoryService.suppressReviewItem(id);
    _reloadMemorySnapshot();
  }

  Future<void> _deleteStoredMemory(String id) async {
    await _sessionMemoryService.deleteMemory(id);
    _reloadMemorySnapshot();
  }

  Future<void> _suppressStoredMemory(MemoryEntry entry) async {
    await _sessionMemoryService.suppressMemory(entry);
    _reloadMemorySnapshot();
  }

  String _memoryTypeLabel(MemoryEntryType type) {
    return switch (type) {
      MemoryEntryType.preference => 'Preference',
      MemoryEntryType.persona => 'Persona',
      MemoryEntryType.topic => 'Topic',
      MemoryEntryType.constraint => 'Constraint',
      MemoryEntryType.fact => 'Fact',
    };
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_chat'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Assistant settings section
          _buildSectionHeader('settings.assistant_section'.tr()),
          const SizedBox(height: 16),
          SegmentedButton<AssistantMode>(
            segments: [
              ButtonSegment(
                value: AssistantMode.general,
                label: Text('settings.assistant_general'.tr()),
                icon: Icon(Icons.chat_outlined),
              ),
              ButtonSegment(
                value: AssistantMode.coding,
                label: Text('settings.assistant_coding'.tr()),
                icon: Icon(Icons.code),
              ),
              ButtonSegment(
                value: AssistantMode.plan,
                label: Text('settings.assistant_plan'.tr()),
                icon: Icon(Icons.route_outlined),
              ),
            ],
            selected: {settings.assistantMode},
            onSelectionChanged: (selection) {
              notifier.updateAssistantMode(selection.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            switch (settings.assistantMode) {
              AssistantMode.general => 'settings.assistant_general_desc'.tr(),
              AssistantMode.coding => 'settings.assistant_coding_desc'.tr(),
              AssistantMode.plan => 'settings.assistant_plan_desc'.tr(),
            },
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
                    'settings.profile_count'.tr(
                      namedArgs: {
                        'count':
                            '${_memorySnapshot.profile.persona.length + _memorySnapshot.profile.preferences.length + _memorySnapshot.profile.doNot.length}',
                      },
                    ),
                  ),
                  Text(
                    'settings.summary_count'.tr(
                      namedArgs: {'count': '${_memorySnapshot.summaryCount}'},
                    ),
                  ),
                  Text(
                    'settings.memory_count'.tr(
                      namedArgs: {'count': '${_memorySnapshot.memoryCount}'},
                    ),
                  ),
                  Text('Review queue: ${_memorySnapshot.reviewCount}'),
                  Text('Suppression rules: ${_memorySnapshot.suppressionCount}'),
                  Text(
                    'settings.last_updated'.tr(
                      namedArgs: {
                        'date': _formatDateTime(_memorySnapshot.lastUpdatedAt),
                      },
                    ),
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
            onChanged: (_) => _autoSaveProfile(),
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
            onChanged: (_) => _autoSaveProfile(),
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
            onChanged: (_) => _autoSaveProfile(),
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
          if (_reviewQueue.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionHeader('Pending memory review'),
            const SizedBox(height: 8),
            ..._reviewQueue.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.text,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_memoryTypeLabel(item.type)} • confidence ${item.confidence.toStringAsFixed(2)} • importance ${item.importance.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () => _keepMemoryReview(item.id),
                            child: const Text('Keep'),
                          ),
                          OutlinedButton(
                            onPressed: () => _deleteMemoryReview(item.id),
                            child: const Text('Delete'),
                          ),
                          OutlinedButton(
                            onPressed: () => _suppressMemoryReview(item.id),
                            child: const Text('Suppress similar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_storedMemories.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionHeader('Stored memories'),
            const SizedBox(height: 8),
            ..._storedMemories.take(12).map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(item.text),
                  subtitle: Text(
                    '${_memoryTypeLabel(item.type)} • confidence ${item.confidence.toStringAsFixed(2)} • updated ${_formatDateTime(item.updatedAt)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'delete':
                          _deleteStoredMemory(item.id);
                          return;
                        case 'suppress':
                          _suppressStoredMemory(item);
                          return;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                      PopupMenuItem(
                        value: 'suppress',
                        child: Text('Suppress similar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_sessionSummaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionHeader('Recent session notes'),
            const SizedBox(height: 8),
            ..._sessionSummaries.take(6).map(
              (summary) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(summary.summary),
                  subtitle: Text(
                    [
                      if (summary.openLoops.isNotEmpty)
                        'Open loops: ${summary.openLoops.join(', ')}',
                      'Updated ${_formatDateTime(summary.updatedAt)}',
                    ].join('\n'),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
