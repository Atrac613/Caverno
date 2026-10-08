import 'dart:convert';
import 'dart:io';

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

Map<String, dynamic> _item(
  String id,
  String quote,
  int line, {
  String? title,
}) => {'id': id, 'title': title ?? id, 'quote': quote, 'line': line};

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
      'recommendation_basis': 'explicit',
      'current': [
        _item('RC1', '| Remote Coding | RC1 | current |', 7),
        _item('RC9', 'invented sentence', 1),
      ],
      'blocked': [_item('HEU3', '| Heuristic Removal | HEU3 | blocked |', 8)],
      'upcoming': [],
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
        'recommendation_basis': 'explicit',
        'current': [],
        'blocked': [],
        'upcoming': [],
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

  test(
    'stores a priority suggestion separately from an explicit next task',
    () async {
      files['/repo/docs/roadmap.md'] = '''
# Watcher roadmap
## Phase 1
- [ ] Retry failed requests
- [ ] Add tests
- [ ] Ignore local config
## Priorities
| High | Phase 1 |
''';
      answer = jsonEncode({
        'recommended': [
          _item('', '- [ ] Retry failed requests', 3, title: 'Retry'),
        ],
        'recommendation_basis': 'priority',
        'current': [],
        'blocked': [],
        'upcoming': [
          _item('', '- [ ] Add tests', 4, title: 'Add tests'),
          _item('', '- [ ] Ignore local config', 5, title: 'Ignore config'),
          _item('', '- [ ] Retry failed requests', 3),
          _item('', 'invented task', 1),
        ],
      });

      final snapshot = await service().refresh(
        projectId: 'p1',
        projectRoot: '/repo',
      );

      expect(snapshot!.status, RoadmapSnapshotStatus.verified);
      expect(
        snapshot.recommendationSource,
        RoadmapRecommendationSource.priority,
      );
      expect(snapshot.recommended!.line, 3);
      expect(snapshot.upcoming.map((item) => item.title), [
        'Add tests',
        'Ignore config',
      ]);
      expect(snapshot.upcoming.map((item) => item.line), [4, 5]);
      expect(snapshot.droppedCount, 1);
      expect(
        repository.snapshotFor('p1')!.recommendationSource,
        RoadmapRecommendationSource.priority,
      );
    },
  );

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

  test('a pin makes a verified item the next task until cleared', () async {
    final subject = service();
    await subject.refresh(projectId: 'p1', projectRoot: '/repo');
    await subject.setPinnedTask('p1', 'HEU3');

    final pinned = subject.cachedSnapshot('p1')!;
    expect(pinned.recommended!.id, 'HEU3');
    expect(pinned.pinned, isTrue);
    expect(
      repository.snapshotFor('p1')!.recommended!.id,
      'RC1',
      reason: 'the stored snapshot stays as extracted',
    );
    expect(
      (await subject.refresh(
        projectId: 'p1',
        projectRoot: '/repo',
      ))!.recommended!.id,
      'HEU3',
    );

    await subject.setPinnedTask('p1', 'RC9');
    expect(
      subject.cachedSnapshot('p1')!.recommended!.id,
      'RC1',
      reason: 'a pin naming no verified item is ignored',
    );
    expect(subject.cachedSnapshot('p1')!.pinned, isFalse);

    await subject.setPinnedTask('p1', null);
    expect(subject.pinnedTaskFor('p1'), isNull);
  });

  test('refuses a roadmap that is a symlink to a file outside', () async {
    final project = Directory.systemTemp.createTempSync('roadmap_project_');
    final outside = Directory.systemTemp.createTempSync('roadmap_outside_');
    addTearDown(() {
      project.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
    final secret = File('${outside.path}/secret.md')..writeAsStringSync('x');
    Link('${project.path}/ROADMAP.md').createSync(secret.path);
    File('${project.path}/PLAN.md').writeAsStringSync('y');

    expect(
      await resolvesInsideProject(project.path, '${project.path}/ROADMAP.md'),
      isFalse,
    );
    expect(
      await resolvesInsideProject(project.path, '${project.path}/PLAN.md'),
      isTrue,
    );
    expect(
      await resolvesInsideProject(project.path, '${project.path}/missing.md'),
      isTrue,
    );
  });

  test('refuses a roadmap path outside the project', () {
    expect(containedPath('/repo', '../secrets.md'), isNull);
    expect(containedPath('/repo', '/etc/passwd'), isNull);
    expect(containedPath('/repo', 'docs/roadmap.md'), '/repo/docs/roadmap.md');
  });
}
