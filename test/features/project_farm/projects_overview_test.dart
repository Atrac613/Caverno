import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/presentation/pages/projects_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = DateTime.utc(2026, 9, 26);
final _project = CodingProject(
  id: 'p1',
  name: 'caverno',
  rootPath: '/work/caverno',
  createdAt: _t,
  updatedAt: _t,
);

RoadmapSnapshot _snapshot(RoadmapSnapshotStatus status) => RoadmapSnapshot(
  projectId: 'p1',
  roadmapPath: 'docs/roadmap.md',
  contentSha256: 'sha',
  extractorVersion: 1,
  model: 'm',
  extractedAt: _t,
  status: status,
  recommended: const RoadmapItemSnapshot(
    id: 'RC1',
    title: 'Evidence',
    quote: 'q',
    line: 1,
  ),
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    RoadmapSnapshot? snapshot,
    int needsApproval = 0,
    void Function(RoadmapSnapshot, RoadmapItemSnapshot)? onStartWork,
    ProjectProposal? proposal,
    VoidCallback? onOpenDashboard,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProjectOverviewTile(
          project: _project,
          snapshot: snapshot,
          refreshing: false,
          running: 1,
          needsApproval: needsApproval,
          onOpenDashboard: onOpenDashboard ?? () {},
          onStartWork: onStartWork ?? (_, _) {},
          proposal: proposal,
        ),
      ),
    ),
  );

  const startKey = ValueKey('projects-overview-p1-start');

  testWidgets('offers Start work only for a verified next task', (
    tester,
  ) async {
    RoadmapItemSnapshot? started;
    await pump(
      tester,
      snapshot: _snapshot(RoadmapSnapshotStatus.verified),
      onStartWork: (_, item) => started = item,
    );
    await tester.tap(find.byKey(startKey));
    expect(started?.id, 'RC1');

    await pump(tester, snapshot: _snapshot(RoadmapSnapshotStatus.unverified));
    expect(find.byKey(startKey), findsNothing);

    await pump(tester);
    expect(find.byKey(startKey), findsNothing);
  });

  testWidgets('tapping the row opens the dashboard', (tester) async {
    var opened = false;
    await pump(tester, onOpenDashboard: () => opened = true);
    await tester.tap(find.text('caverno'));
    expect(opened, isTrue);
  });

  group('startableItem', () {
    final snapshot = _snapshot(RoadmapSnapshotStatus.verified).copyWith(
      current: const [
        RoadmapItemSnapshot(id: 'F5', title: 'Split', quote: 'F5', line: 2),
      ],
      blocked: const [
        RoadmapItemSnapshot(id: 'HEU3', title: 'Claims', quote: 'H', line: 3),
      ],
    );
    ProjectProposal proposal(String taskId, {String? error}) => ProjectProposal(
      projectId: 'p1',
      inputHash: 'h',
      proposedAt: _t,
      taskId: taskId,
      automatability: 'needsHuman',
      error: error,
    );

    test('prefers a proposed in-progress item', () {
      expect(startableItem(snapshot, proposal('F5'))?.id, 'F5');
    });

    test('falls back to the verified next task', () {
      expect(startableItem(snapshot, null)?.id, 'RC1');
      expect(
        startableItem(snapshot, proposal('HEU3'))?.id,
        'RC1',
        reason: 'blocked items are never startable',
      );
      expect(startableItem(snapshot, proposal('F5', error: 'bad'))?.id, 'RC1');
    });

    test('offers nothing without a verified snapshot', () {
      expect(
        startableItem(_snapshot(RoadmapSnapshotStatus.unverified), null),
        isNull,
      );
    });
  });

  testWidgets('shows the proposal with its automatability label', (
    tester,
  ) async {
    await pump(
      tester,
      snapshot: _snapshot(RoadmapSnapshotStatus.verified),
      proposal: ProjectProposal(
        projectId: 'p1',
        inputHash: 'h',
        proposedAt: _t,
        taskId: 'RC1',
        rationale: 'The roadmap selects it.',
        automatability: 'needsHuman',
      ),
    );
    expect(
      find.byKey(const ValueKey('projects-overview-p1-needsHuman')),
      findsOneWidget,
    );
  });

  group('proposalIsStale', () {
    final proposal = ProjectProposal(
      projectId: 'p1',
      inputHash: 'h',
      proposedAt: _t,
    );
    final later = _t.add(const Duration(minutes: 5));
    final earlier = _t.subtract(const Duration(minutes: 5));

    test('flags a newer roadmap read or a goal finished since', () {
      final snapshot = _snapshot(RoadmapSnapshotStatus.verified);
      expect(
        proposalIsStale(
          proposal,
          snapshot: snapshot.copyWith(extractedAt: later),
          goalCompletions: const [],
        ),
        isTrue,
      );
      expect(
        proposalIsStale(
          proposal,
          snapshot: snapshot.copyWith(extractedAt: earlier),
          goalCompletions: [later],
        ),
        isTrue,
      );
    });

    test('keeps a proposal newer than both current', () {
      expect(
        proposalIsStale(
          proposal,
          snapshot: _snapshot(
            RoadmapSnapshotStatus.verified,
          ).copyWith(extractedAt: earlier),
          goalCompletions: [earlier],
        ),
        isFalse,
      );
      expect(
        proposalIsStale(null, snapshot: null, goalCompletions: [later]),
        isFalse,
      );
    });
  });
}
