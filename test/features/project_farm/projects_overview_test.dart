import 'package:caverno/features/chat/domain/entities/coding_project.dart';
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
    ValueChanged<RoadmapSnapshot>? onStartWork,
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
          onStartWork: onStartWork ?? (_) {},
        ),
      ),
    ),
  );

  const startKey = ValueKey('projects-overview-p1-start');

  testWidgets('offers Start work only for a verified next task', (
    tester,
  ) async {
    RoadmapSnapshot? started;
    await pump(
      tester,
      snapshot: _snapshot(RoadmapSnapshotStatus.verified),
      onStartWork: (s) => started = s,
    );
    await tester.tap(find.byKey(startKey));
    expect(started?.recommended?.id, 'RC1');

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
}
