import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/entities/skill_catalog_entry.dart';
import 'package:caverno/features/chat/presentation/providers/skill_catalog_provider.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:caverno/features/settings/presentation/pages/skill_catalog_sheet.dart';

void main() {
  const conflictEntry = SkillCatalogEntry(
    assetPath: 'assets/skills/github_pr_conflict.md',
    name: 'GitHub PR conflict resolution',
    description: 'Resolve merge conflicts with the gh CLI',
    whenToUse: 'When asked to fix conflicts on a pull request',
    markdown: '---\nname: GitHub PR conflict resolution\n---\n\nUse gh.',
  );
  const triageEntry = SkillCatalogEntry(
    assetPath: 'assets/skills/github_ci_triage.md',
    name: 'GitHub CI failure triage',
    description: 'Find and fix a failing CI check',
    whenToUse: 'When a CI check is failing',
    markdown: '---\nname: GitHub CI failure triage\n---\n\nUse gh pr checks.',
  );

  /// Opens the sheet and hands back a holder the test reads after the sheet
  /// pops, since the selection only exists once the route closes.
  Future<_SelectionHolder> pumpSheet(
    WidgetTester tester, {
    required AsyncValue<List<SkillCatalogEntry>> catalog,
    List<Skill> existingSkills = const [],
  }) async {
    final holder = _SelectionHolder();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          skillCatalogProvider.overrideWith((ref) async {
            if (catalog case AsyncError(:final error)) {
              throw error;
            }
            return catalog.value ?? const <SkillCatalogEntry>[];
          }),
          skillsNotifierProvider.overrideWith(
            () => _StubSkillsNotifier(existingSkills),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  holder.selection = await SkillCatalogSheet.show(context);
                  holder.completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return holder;
  }

  testWidgets('lists prebuilt skills alongside the blank option', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      catalog: const AsyncValue.data([conflictEntry, triageEntry]),
    );

    expect(find.text('Blank skill'), findsOneWidget);
    expect(find.text(conflictEntry.name), findsOneWidget);
    expect(find.text(triageEntry.name), findsOneWidget);
    expect(find.text(conflictEntry.description), findsOneWidget);
  });

  testWidgets('returns the entry markdown so the editor opens on it', (
    tester,
  ) async {
    final holder = await pumpSheet(
      tester,
      catalog: const AsyncValue.data([conflictEntry]),
    );

    await tester.tap(find.text(conflictEntry.name));
    await tester.pumpAndSettle();

    expect(holder.completed, isTrue);
    // The editor opens on the asset text verbatim, so no conversion step can
    // change what the user reviews before saving.
    expect(holder.selection?.markdown, conflictEntry.markdown);
  });

  testWidgets('blank returns no markdown so the editor keeps its placeholder', (
    tester,
  ) async {
    final holder = await pumpSheet(
      tester,
      catalog: const AsyncValue.data([conflictEntry]),
    );

    await tester.tap(find.text('Blank skill'));
    await tester.pumpAndSettle();

    expect(holder.completed, isTrue);
    expect(holder.selection, isNotNull);
    expect(holder.selection?.markdown, isNull);
  });

  testWidgets('marks an already-added skill and blocks re-adding it', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      catalog: const AsyncValue.data([conflictEntry, triageEntry]),
      existingSkills: [
        Skill(
          id: 'saved',
          // Matching is name-based and case-insensitive.
          name: conflictEntry.name.toUpperCase(),
          createdAt: DateTime(2026, 8, 17),
          updatedAt: DateTime(2026, 8, 17),
        ),
      ],
    );

    expect(find.text('Added'), findsOneWidget);
    final blocked = tester.widget<InkWell>(
      find.ancestor(
        of: find.text(conflictEntry.name),
        matching: find.byType(InkWell),
      ),
    );
    expect(blocked.onTap, isNull);
  });

  testWidgets('keeps the blank option when the catalog fails to load', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      catalog: AsyncValue.error(Exception('bundle missing'), StackTrace.empty),
    );

    // A broken catalog must never block adding a skill by hand.
    expect(find.text('Blank skill'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsOneWidget);
  });
}

class _SelectionHolder {
  SkillCatalogSelection? selection;
  bool completed = false;
}

class _StubSkillsNotifier extends SkillsNotifier {
  _StubSkillsNotifier(this._skills);

  final List<Skill> _skills;

  @override
  SkillsState build() => SkillsState(skills: _skills);
}
