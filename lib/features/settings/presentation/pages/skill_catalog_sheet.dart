import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/domain/entities/skill_catalog_entry.dart';
import '../../../chat/presentation/providers/skill_catalog_provider.dart';
import '../../../chat/presentation/providers/skills_notifier.dart';

/// What the user picked in the catalog sheet.
///
/// A blank pick carries no markdown so the editor falls back to its own
/// placeholder, which keeps "Add Skill" working exactly as before.
final class SkillCatalogSelection {
  const SkillCatalogSelection.blank() : markdown = null;
  const SkillCatalogSelection.entry(this.markdown);

  final String? markdown;
}

/// Lets the user start a new skill from a prebuilt one.
///
/// Picking an entry only hands its markdown to the editor: nothing is saved
/// here, so the catalog cannot introduce a second write path. Entries already
/// present in the user's skills are shown as added and cannot be picked again.
class SkillCatalogSheet extends ConsumerWidget {
  const SkillCatalogSheet({super.key});

  static Future<SkillCatalogSelection?> show(BuildContext context) {
    return showModalBottomSheet<SkillCatalogSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const SkillCatalogSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalog = ref.watch(skillCatalogProvider);
    final existingNames = ref
        .watch(skillsNotifierProvider)
        .skills
        .map((skill) => skill.normalizedName.toLowerCase())
        .toSet();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add Skill',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _BlankSkillCard(
                  onTap: () => Navigator.pop(
                    context,
                    const SkillCatalogSelection.blank(),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Start from a prebuilt skill',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                // A catalog that fails to load must not block adding a skill:
                // the blank option above stays available in every state.
                ...switch (catalog) {
                  AsyncData(:final value) when value.isEmpty => [
                    const _CatalogNotice('No prebuilt skills are bundled.'),
                  ],
                  AsyncData(:final value) => [
                    for (final entry in value) ...[
                      _CatalogEntryCard(
                        entry: entry,
                        alreadyAdded: existingNames.contains(entry.matchKey),
                        onTap: () => Navigator.pop(
                          context,
                          SkillCatalogSelection.entry(entry.markdown),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  AsyncError() => [
                    const _CatalogNotice(
                      'Prebuilt skills could not be loaded. You can still '
                      'write one from scratch.',
                    ),
                  ],
                  _ => [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlankSkillCard extends StatelessWidget {
  const _BlankSkillCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          Icons.edit_note_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Blank skill'),
        subtitle: const Text('Write your own instructions from scratch'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _CatalogNotice extends StatelessWidget {
  const _CatalogNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CatalogEntryCard extends StatelessWidget {
  const _CatalogEntryCard({
    required this.entry,
    required this.alreadyAdded,
    required this.onTap,
  });

  final SkillCatalogEntry entry;
  final bool alreadyAdded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: alreadyAdded ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  color: alreadyAdded
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.normalizedName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (alreadyAdded)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'Added',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (entry.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(entry.description.trim()),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
