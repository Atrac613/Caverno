import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/built_in_tool_info.dart';
import '../providers/settings_notifier.dart';

class BuiltInToolsSettingsPage extends ConsumerWidget {
  const BuiltInToolsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final disabled = settings.disabledBuiltInToolsSet;
    final totalCount = BuiltInToolRegistry.tools.length;
    final enabledCount = totalCount - disabled.length;
    final toolsByCategory = BuiltInToolRegistry.toolsByCategory;

    return Scaffold(
      appBar: AppBar(title: Text('settings.built_in_tools'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'settings.built_in_tools_summary'.tr(
              namedArgs: {
                'enabled': '$enabledCount',
                'total': '$totalCount',
              },
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final category in BuiltInToolRegistry.categories)
            _CategorySection(
              category: category,
              tools: toolsByCategory[category] ?? const [],
              disabledTools: disabled,
              onToggleTool: notifier.toggleBuiltInTool,
              onToggleCategory: (categoryName, enabled) {
                final names =
                    BuiltInToolRegistry.toolNamesForCategory(categoryName);
                notifier.setBuiltInToolsCategoryDisabled(names, !enabled);
              },
            ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.tools,
    required this.disabledTools,
    required this.onToggleTool,
    required this.onToggleCategory,
  });

  final String category;
  final List<BuiltInToolInfo> tools;
  final Set<String> disabledTools;
  final void Function(String toolName, bool enabled) onToggleTool;
  final void Function(String category, bool enabled) onToggleCategory;

  @override
  Widget build(BuildContext context) {
    final enabledInCategory =
        tools.where((t) => !disabledTools.contains(t.name)).length;
    final noneEnabled = enabledInCategory == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          BuiltInToolRegistry.categoryIcon(category),
          color: noneEnabled
              ? Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(100)
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text('settings.tool_category_$category'.tr()),
        subtitle: Text(
          'settings.built_in_tools_category_enabled'.tr(
            namedArgs: {
              'enabled': '$enabledInCategory',
              'total': '${tools.length}',
            },
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Switch(
          value: !noneEnabled,
          onChanged: (value) => onToggleCategory(category, value),
        ),
        children: [
          for (final tool in tools)
            SwitchListTile(
              title: Text(
                tool.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              subtitle: Text(tool.descriptionKey.tr()),
              value: !disabledTools.contains(tool.name),
              onChanged: (value) => onToggleTool(tool.name, value),
              dense: true,
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
