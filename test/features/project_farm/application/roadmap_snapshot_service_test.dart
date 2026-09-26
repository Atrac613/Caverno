import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/project_farm/application/roadmap_snapshot_service.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/domain/roadmap_next_task_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _roadmap = '''
# Roadmap

### Recommended Next Slice

**Recommended next slice: RC1 signed-device evidence.**

| Remote Coding | RC1 | current | Transport work. |
| Heuristic Removal | HEU3 | blocked | Completion claims. |
''';

Map<String, dynamic> _item(String id, String quote, int line) => {
  'id': id,
  'title': id,
  'quote': quote,
  'line': line,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RoadmapSnapshotRepository repository;
  late Map<String, String> files;
  late List<ModelUsageRole> roles;
  late String answer;
  late String model;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = RoadmapSnapshotRepository(
      await SharedPreferences.getInstance(),
    );
    files = {'/repo/docs/roadmap.md': _roadmap};
    roles = [];
    model = 'model-a';
    answer = jsonEncode({
      'recommended': [
        _item('RC1', 'Recommended next slice: RC1 signed-device evidence.', 5),
      ],
      'current': [
        _item('RC1', '| Remote Coding | RC1 | current |', 7),
        _item('RC9', 'invented sentence', 1),
      ],
      'blocked': [_item('HEU3', '| Heuristic Removal | HEU3 | blocked |', 8)],
    });
  });

  RoadmapSnapshotService service() => RoadmapSnapshotService(
    repository: repository,
    ensureAccess: (_) async => true,
    readFile: (path) async => files[path],
    extractor: () => RoadmapNextTaskExtractor(
      complete:
          ({
            required system,
            required user,
            required schemaName,
            required schema,
            required maxTokens,
          }) async {
            roles.add(ModelUsageRole.current);
            return RoadmapCompletion(content: answer, finishReason: 'stop');
          },
    ),
    model: () => model,
    now: () => DateTime.utc(2026, 9, 26),
  );

  test('stores a verified recommendation with the source line', () async {
    final snapshot = await service().refresh(
      projectId: 'p1',
      projectRoot: '/repo',
    );

    expect(snapshot!.status, RoadmapSnapshotStatus.verified);
    expect(snapshot.roadmapPath, 'docs/roadmap.md');
    expect(snapshot.recommended!.id, 'RC1');
    expect(snapshot.recommended!.line, 5);
    expect(snapshot.current.map((item) => item.id), ['RC1']);
    expect(snapshot.blocked.map((item) => item.id), ['HEU3']);
    expect(snapshot.droppedCount, 1, reason: 'RC9 quote is not in the source');
    expect(roles, [ModelUsageRole.projectState]);
    expect(repository.snapshotFor('p1'), snapshot);
  });

  test('reuses the cached snapshot until the content changes', () async {
    final subject = service();
    await subject.refresh(projectId: 'p1', projectRoot: '/repo');
    await subject.refresh(projectId: 'p1', projectRoot: '/repo');
    expect(roles, hasLength(1));

    files['/repo/docs/roadmap.md'] = '$_roadmap\nOne more line.\n';
    await subject.refresh(projectId: 'p1', projectRoot: '/repo');
    expect(roles, hasLength(2));

    model = 'model-b';
    await subject.refresh(projectId: 'p1', projectRoot: '/repo');
    expect(roles, hasLength(3));
  });

  test(
    'marks a recommendation whose quote lacks its id as unverified',
    () async {
      answer = jsonEncode({
        'recommended': [_item('ANA3', '# Roadmap', 1)],
        'current': [],
        'blocked': [],
      });

      final snapshot = await service().refresh(
        projectId: 'p1',
        projectRoot: '/repo',
      );

      expect(snapshot!.status, RoadmapSnapshotStatus.unverified);
      expect(snapshot.recommended!.verified, isFalse);
      expect(snapshot.recommended!.line, isNull);
    },
  );

  test('records an unparseable answer as failed', () async {
    answer = '{"recommended": [';

    final snapshot = await service().refresh(
      projectId: 'p1',
      projectRoot: '/repo',
    );

    expect(snapshot!.status, RoadmapSnapshotStatus.failed);
    expect(snapshot.error, isNotNull);
  });

  test('returns null when the project has no roadmap document', () async {
    files.clear();
    expect(
      await service().refresh(projectId: 'p1', projectRoot: '/repo'),
      isNull,
    );
    expect(roles, isEmpty);
  });

  test('uses a configured roadmap path', () async {
    files['/repo/PLAN.md'] = _roadmap;
    files.remove('/repo/docs/roadmap.md');
    final subject = service();
    await subject.setRoadmapPath('p1', 'PLAN.md');

    final snapshot = await subject.refresh(
      projectId: 'p1',
      projectRoot: '/repo',
    );
    expect(snapshot!.roadmapPath, 'PLAN.md');
  });

  test(
    'shares one run between concurrent refreshes and then releases it',
    () async {
      final subject = service();
      final results = await Future.wait([
        subject.refresh(projectId: 'p1', projectRoot: '/repo'),
        subject.refresh(projectId: 'p1', projectRoot: '/repo', force: true),
      ]);
      expect(identical(results[0], results[1]), isTrue);
      expect(roles, hasLength(1));

      await subject.refresh(projectId: 'p1', projectRoot: '/repo', force: true);
      expect(roles, hasLength(2));
    },
  );

  test('refuses a roadmap path outside the project', () {
    expect(containedPath('/repo', '../secrets.md'), isNull);
    expect(containedPath('/repo', '/etc/passwd'), isNull);
    expect(containedPath('/repo', 'docs/roadmap.md'), '/repo/docs/roadmap.md');
  });
}
