import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/domain/entities/skill.dart';
import '../../../chat/domain/services/skill_markdown_parser.dart';
import '../../../chat/presentation/providers/skills_notifier.dart';

class SkillsSettingsPage extends ConsumerWidget {
  const SkillsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsState = ref.watch(skillsNotifierProvider);
    final notifier = ref.read(skillsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Skills')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add Skill'),
        onPressed: () => _showSkillEditor(context, notifier),
      ),
      body: skillsState.skills.isEmpty
          ? const _EmptySkillsView()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: skillsState.skills.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final skill = skillsState.skills[index];
                return _SkillCard(
                  skill: skill,
                  onToggle: (enabled) =>
                      notifier.toggleSkill(skill.id, enabled),
                  onEdit: () =>
                      _showSkillEditor(context, notifier, existingSkill: skill),
                  onDelete: () => _confirmDeleteSkill(context, notifier, skill),
                );
              },
            ),
    );
  }

  static Future<void> _showSkillEditor(
    BuildContext context,
    SkillsNotifier notifier, {
    Skill? existingSkill,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SkillEditorSheet(existingSkill: existingSkill),
    );
    if (saved != true || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(existingSkill == null ? 'Skill added' : 'Skill saved'),
      ),
    );
  }

  static Future<void> _confirmDeleteSkill(
    BuildContext context,
    SkillsNotifier notifier,
    Skill skill,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete skill?'),
        content: Text('Delete "${skill.normalizedName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await notifier.deleteSkill(skill.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Skill deleted')));
  }
}

class _EmptySkillsView extends StatelessWidget {
  const _EmptySkillsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No skills yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add reusable markdown instructions with name, description, and whenToUse frontmatter.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Skill skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(
                Icons.auto_awesome_outlined,
                color: skill.enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.normalizedName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (skill.normalizedDescription.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(skill.normalizedDescription),
                  ],
                  if (skill.normalizedWhenToUse.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'When: ${skill.normalizedWhenToUse}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(value: skill.enabled, onChanged: onToggle),
            PopupMenuButton<_SkillMenuAction>(
              onSelected: (action) {
                switch (action) {
                  case _SkillMenuAction.edit:
                    onEdit();
                  case _SkillMenuAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _SkillMenuAction.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem(
                  value: _SkillMenuAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillEditorSheet extends ConsumerStatefulWidget {
  const _SkillEditorSheet({this.existingSkill});

  final Skill? existingSkill;

  @override
  ConsumerState<_SkillEditorSheet> createState() => _SkillEditorSheetState();
}

class _SkillEditorSheetState extends ConsumerState<_SkillEditorSheet> {
  late final TextEditingController _markdownController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _markdownController = TextEditingController(
      text: widget.existingSkill == null
          ? _defaultMarkdown()
          : SkillMarkdownParser.toMarkdown(widget.existingSkill!),
    );
  }

  @override
  void dispose() {
    _markdownController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final markdown = _markdownController.text.trim();
    if (markdown.isEmpty) {
      setState(() => _errorText = 'Markdown is required.');
      return;
    }
    final parsed = SkillMarkdownParser.parse(markdown);
    if (parsed.name.trim().isEmpty) {
      setState(() => _errorText = 'Skill name is required.');
      return;
    }
    await ref
        .read(skillsNotifierProvider.notifier)
        .upsertMarkdown(
          existingId: widget.existingSkill?.id,
          markdown: markdown,
        );
    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existingSkill == null ? 'Add Skill' : 'Edit Skill',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _markdownController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: _defaultMarkdown(),
                    errorText: _errorText,
                    border: const OutlineInputBorder(),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Skill'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _defaultMarkdown() {
    return '''---
name: Example Skill
description: Short summary of what this skill helps with
whenToUse: Use when the task matches this repeated workflow
---

Write the full reusable instructions here.''';
  }
}

enum _SkillMenuAction { edit, delete }
