import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../routines/domain/services/routine_computer_use_action_allowlist.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/settings_notifier.dart';

class RoutineComputerUseAllowlistPage extends ConsumerWidget {
  const RoutineComputerUseAllowlistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final entries = settings.routineComputerUseActionAllowlist;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.routine_computer_use_allowlist'.tr()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editEntry(context, notifier),
        icon: const Icon(Icons.add),
        label: Text('settings.routine_computer_use_allowlist_add'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'settings.routine_computer_use_allowlist_help'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'settings.routine_computer_use_allowlist_empty'.tr(),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final entry in entries)
              _AllowlistEntryCard(
                entry: entry,
                onToggle: (enabled) =>
                    notifier.toggleRoutineComputerUseActionAllowlistEntry(
                      entry.id,
                      enabled,
                    ),
                onEdit: () => _editEntry(context, notifier, entry: entry),
                onDelete: () => notifier
                    .removeRoutineComputerUseActionAllowlistEntry(entry.id),
              ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _editEntry(
    BuildContext context,
    SettingsNotifier notifier, {
    RoutineComputerUseActionAllowlistEntry? entry,
  }) async {
    final result =
        await showModalBottomSheet<RoutineComputerUseActionAllowlistEntry>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _AllowlistEntryEditorSheet(initialEntry: entry),
        );
    if (result == null) {
      return;
    }
    await notifier.upsertRoutineComputerUseActionAllowlistEntry(result);
  }
}

class _AllowlistEntryCard extends StatelessWidget {
  const _AllowlistEntryCard({
    required this.entry,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final RoutineComputerUseActionAllowlistEntry entry;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          SwitchListTile(
            value: entry.enabled,
            onChanged: onToggle,
            title: Text(_entryTitle(entry)),
            subtitle: Text(_entrySummary(entry)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'routines.edit'.tr(),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'settings.routine_computer_use_allowlist_delete'
                      .tr(),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _entryTitle(RoutineComputerUseActionAllowlistEntry entry) {
    final label = entry.normalizedLabel;
    if (label.isNotEmpty) {
      return label;
    }
    final toolName = entry.normalizedToolName;
    return toolName.isEmpty
        ? 'settings.routine_computer_use_allowlist_rule'.tr()
        : toolName;
  }

  String _entrySummary(RoutineComputerUseActionAllowlistEntry entry) {
    final parts = <String>[
      if (entry.normalizedToolName.isNotEmpty) entry.normalizedToolName,
      if (entry.targetLabelContains.trim().isNotEmpty)
        'label contains "${entry.targetLabelContains.trim()}"',
      if (entry.targetRole.trim().isNotEmpty) 'role=${entry.targetRole.trim()}',
      if (entry.targetAction.trim().isNotEmpty)
        'action=${entry.targetAction.trim()}',
      if (entry.targetRisk.trim().isNotEmpty) 'risk=${entry.targetRisk.trim()}',
      if (entry.appNameContains.trim().isNotEmpty)
        'app contains "${entry.appNameContains.trim()}"',
      if (entry.appBundleId.trim().isNotEmpty)
        'bundle=${entry.appBundleId.trim()}',
      if (entry.windowTitleContains.trim().isNotEmpty)
        'window contains "${entry.windowTitleContains.trim()}"',
      if (entry.urlHost.trim().isNotEmpty) 'url host=${entry.urlHost.trim()}',
      if (entry.urlStartsWith.trim().isNotEmpty)
        'url starts with "${entry.urlStartsWith.trim()}"',
      if (entry.exactText.isNotEmpty)
        'exact text length=${entry.exactText.length}',
      if (entry.normalizedToolName == 'computer_type_text' &&
          entry.exactText.isEmpty)
        'settings.routine_computer_use_allowlist_any_text_allowed'.tr(),
    ];
    return parts.isEmpty
        ? 'settings.routine_computer_use_allowlist_no_boundary'.tr()
        : parts.join(' / ');
  }
}

class _AllowlistEntryEditorSheet extends StatefulWidget {
  const _AllowlistEntryEditorSheet({this.initialEntry});

  final RoutineComputerUseActionAllowlistEntry? initialEntry;

  @override
  State<_AllowlistEntryEditorSheet> createState() =>
      _AllowlistEntryEditorSheetState();
}

class _AllowlistEntryEditorSheetState
    extends State<_AllowlistEntryEditorSheet> {
  static const _uuid = Uuid();
  static final List<String> _actionToolNames = <String>[
    RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName,
    ...MacosComputerUseToolPolicy.allToolNames.where(
      MacosComputerUseToolPolicy.requiresUserApproval,
    ),
  ]..sort();
  static const List<String> _riskOptions = [
    '',
    'input',
    'public_action',
    'sensitive',
    'unknown',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _targetLabelController;
  late final TextEditingController _targetRoleController;
  late final TextEditingController _targetActionController;
  late final TextEditingController _appNameController;
  late final TextEditingController _appBundleIdController;
  late final TextEditingController _windowTitleController;
  late final TextEditingController _urlHostController;
  late final TextEditingController _urlStartsWithController;
  late final TextEditingController _exactTextController;
  late bool _enabled;
  late String _toolName;
  late String _targetRisk;
  bool _boundaryError = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _labelController = TextEditingController(text: entry?.label ?? '');
    _targetLabelController = TextEditingController(
      text: entry?.targetLabelContains ?? '',
    );
    _targetRoleController = TextEditingController(
      text: entry?.targetRole ?? '',
    );
    _targetActionController = TextEditingController(
      text: entry?.targetAction ?? '',
    );
    _appNameController = TextEditingController(
      text: entry?.appNameContains ?? '',
    );
    _appBundleIdController = TextEditingController(
      text: entry?.appBundleId ?? '',
    );
    _windowTitleController = TextEditingController(
      text: entry?.windowTitleContains ?? '',
    );
    _urlHostController = TextEditingController(text: entry?.urlHost ?? '');
    _urlStartsWithController = TextEditingController(
      text: entry?.urlStartsWith ?? '',
    );
    _exactTextController = TextEditingController(text: entry?.exactText ?? '');
    _enabled = entry?.enabled ?? true;
    _toolName = entry?.normalizedToolName.isNotEmpty == true
        ? entry!.normalizedToolName
        : 'computer_click';
    _targetRisk = _riskOptions.contains(entry?.targetRisk)
        ? entry!.targetRisk
        : '';
  }

  @override
  void dispose() {
    _labelController.dispose();
    _targetLabelController.dispose();
    _targetRoleController.dispose();
    _targetActionController.dispose();
    _appNameController.dispose();
    _appBundleIdController.dispose();
    _windowTitleController.dispose();
    _urlHostController.dispose();
    _urlStartsWithController.dispose();
    _exactTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialEntry == null
                      ? 'settings.routine_computer_use_allowlist_add'.tr()
                      : 'settings.routine_computer_use_allowlist_edit'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _labelController,
                  decoration: InputDecoration(
                    labelText: 'settings.routine_computer_use_allowlist_label'
                        .tr(),
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _toolName,
                  decoration: InputDecoration(
                    labelText: 'settings.routine_computer_use_allowlist_tool'
                        .tr(),
                    border: const OutlineInputBorder(),
                  ),
                  items: _actionToolNames
                      .map(
                        (toolName) => DropdownMenuItem(
                          value: toolName,
                          child: Text(toolName),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _toolName = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'settings.routine_computer_use_allowlist_enabled'.tr(),
                  ),
                  value: _enabled,
                  onChanged: (value) {
                    setState(() {
                      _enabled = value;
                    });
                  },
                ),
                const Divider(),
                Text(
                  'settings.routine_computer_use_allowlist_boundaries'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _targetLabelController,
                  decoration: InputDecoration(
                    labelText:
                        'settings.routine_computer_use_allowlist_target_label'
                            .tr(),
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _targetRoleController,
                        decoration: InputDecoration(
                          labelText:
                              'settings.routine_computer_use_allowlist_target_role'
                                  .tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _targetActionController,
                        decoration: InputDecoration(
                          labelText:
                              'settings.routine_computer_use_allowlist_target_action'
                                  .tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _targetRisk,
                  decoration: InputDecoration(
                    labelText:
                        'settings.routine_computer_use_allowlist_target_risk'
                            .tr(),
                    border: const OutlineInputBorder(),
                  ),
                  items: _riskOptions
                      .map(
                        (risk) => DropdownMenuItem(
                          value: risk,
                          child: Text(
                            risk.isEmpty
                                ? 'settings.routine_computer_use_allowlist_any'
                                      .tr()
                                : risk,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setState(() {
                      _targetRisk = value ?? '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _appNameController,
                        decoration: InputDecoration(
                          labelText:
                              'settings.routine_computer_use_allowlist_app_name'
                                  .tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _appBundleIdController,
                        decoration: InputDecoration(
                          labelText:
                              'settings.routine_computer_use_allowlist_bundle_id'
                                  .tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _windowTitleController,
                  decoration: InputDecoration(
                    labelText:
                        'settings.routine_computer_use_allowlist_window_title'
                            .tr(),
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _urlHostController,
                        decoration: InputDecoration(
                          labelText:
                              'settings.routine_computer_use_allowlist_url_host'
                                  .tr(),
                          border: const OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _urlStartsWithController,
                        decoration: InputDecoration(
                          labelText:
                              'settings.routine_computer_use_allowlist_url_starts_with'
                                  .tr(),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _exactTextController,
                  decoration: InputDecoration(
                    labelText:
                        'settings.routine_computer_use_allowlist_exact_text'
                            .tr(),
                    helperText:
                        'settings.routine_computer_use_allowlist_exact_text_help'
                            .tr(),
                    border: const OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                if (_boundaryError) ...[
                  const SizedBox(height: 8),
                  Text(
                    'settings.routine_computer_use_allowlist_boundary_required'
                        .tr(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('common.cancel'.tr()),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      child: Text('common.save'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final entry = RoutineComputerUseActionAllowlistEntry(
      id: widget.initialEntry?.id ?? _uuid.v4(),
      enabled: _enabled,
      label: _labelController.text.trim(),
      toolName: _toolName,
      targetLabelContains: _targetLabelController.text.trim(),
      targetRole: _targetRoleController.text.trim(),
      targetAction: _targetActionController.text.trim(),
      targetRisk: _targetRisk.trim(),
      appNameContains: _appNameController.text.trim(),
      appBundleId: _appBundleIdController.text.trim(),
      windowTitleContains: _windowTitleController.text.trim(),
      urlHost: _urlHostController.text.trim(),
      urlStartsWith: _urlStartsWithController.text.trim(),
      exactText: _exactTextController.text,
    );
    if (!entry.hasBoundary) {
      setState(() {
        _boundaryError = true;
      });
      return;
    }

    Navigator.of(context).pop(entry);
  }
}
