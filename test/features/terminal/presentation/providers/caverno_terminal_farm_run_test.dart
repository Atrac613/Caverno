import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/presentation/providers/caverno_terminal_farm_run.dart';
import 'package:flutter_test/flutter_test.dart';

RoadmapItemSnapshot _item(String id) =>
    RoadmapItemSnapshot(id: id, title: '$id title', quote: '$id quote');

RoadmapSnapshot _snapshot({RoadmapItemSnapshot? recommended}) =>
    RoadmapSnapshot(
      projectId: 'p1',
      roadmapPath: 'ROADMAP.md',
      contentSha256: 'sha',
      extractorVersion: 1,
      model: 'm',
      extractedAt: DateTime.utc(2026),
      status: RoadmapSnapshotStatus.verified,
      recommended: recommended,
      current: [_item('CUR')],
      upcoming: [_item('NEXT')],
      blocked: [_item('HELD')],
    );

Matcher _fails(String code, int exitCode) => throwsA(
  isA<CavernoCliFailure>()
      .having((failure) => failure.code, 'code', code)
      .having((failure) => failure.exitCode, 'exitCode', exitCode),
);

void main() {
  test('defaults to the recommended item', () {
    expect(
      selectFarmRoadmapItem(_snapshot(recommended: _item('REC')), null).id,
      'REC',
    );
  });

  test('selects a current or upcoming item by id, ignoring case', () {
    final snapshot = _snapshot(recommended: _item('REC'));
    expect(selectFarmRoadmapItem(snapshot, 'cur').id, 'CUR');
    expect(selectFarmRoadmapItem(snapshot, 'NEXT').id, 'NEXT');
  });

  test('refuses a blocked, unknown, or missing item', () {
    final snapshot = _snapshot();
    expect(
      () => selectFarmRoadmapItem(snapshot, 'HELD'),
      _fails('roadmap_item_blocked', CavernoCliExitCode.blocked),
    );
    expect(
      () => selectFarmRoadmapItem(snapshot, 'NOPE'),
      _fails('roadmap_item_not_found', CavernoCliExitCode.input),
    );
    expect(
      () => selectFarmRoadmapItem(snapshot, null),
      _fails('roadmap_item_unavailable', CavernoCliExitCode.blocked),
    );
  });
}
