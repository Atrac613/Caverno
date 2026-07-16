import 'dart:io';

import 'package:caverno/core/services/security_scoped_bookmark_service.dart';
import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecurityScopedBookmarkService extends SecurityScopedBookmarkService {
  final Map<String, String?> createdBookmarks = {};
  final Map<String, SecurityScopedBookmarkAccessResult> accessResults = {};

  @override
  Future<String?> createBookmark(String path) async {
    return createdBookmarks[path];
  }

  @override
  Future<SecurityScopedBookmarkAccessResult> startAccessingBookmark(
    String bookmark,
  ) async {
    return accessResults[bookmark] ??
        const SecurityScopedBookmarkAccessResult.success();
  }
}

class _FailingCodingProjectRepository implements CodingProjectRepositoryApi {
  @override
  List<CodingProject> loadAll() => const <CodingProject>[];

  @override
  Future<void> saveAll(List<CodingProject> projects) {
    throw const FileSystemException('Project persistence failed');
  }
}

void main() {
  late SharedPreferences prefs;
  late _FakeSecurityScopedBookmarkService bookmarkService;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    bookmarkService = _FakeSecurityScopedBookmarkService();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        securityScopedBookmarkServiceProvider.overrideWithValue(
          bookmarkService,
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('addProject stores a security-scoped bookmark', () async {
    const projectPath = '/Users/test/Documents/sample_project';
    bookmarkService.createdBookmarks[projectPath] = 'bookmark-1';

    final notifier = container.read(codingProjectsNotifierProvider.notifier);
    final project = await notifier.addProject(projectPath);

    expect(project, isNotNull);
    expect(project!.securityScopedBookmark, 'bookmark-1');
    final state = container.read(codingProjectsNotifierProvider);
    expect(state.projects.single.securityScopedBookmark, 'bookmark-1');
  });

  test(
    'ensureTerminalProject persists and reuses the terminal project',
    () async {
      const projectPath = '/tmp/terminal-project';
      final project = await container
          .read(codingProjectsNotifierProvider.notifier)
          .ensureTerminalProject(projectPath);

      expect(project.rootPath, projectPath);
      expect(project.securityScopedBookmark, isNull);
      expect(
        container.read(codingProjectsNotifierProvider).selectedProject,
        same(project),
      );

      final repeated = await container
          .read(codingProjectsNotifierProvider.notifier)
          .ensureTerminalProject(projectPath);
      expect(repeated.id, project.id);
      expect(
        container.read(codingProjectsNotifierProvider).projects,
        hasLength(1),
      );

      final reloaded = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          securityScopedBookmarkServiceProvider.overrideWithValue(
            bookmarkService,
          ),
        ],
      );
      addTearDown(reloaded.dispose);
      final reloadedProject = reloaded
          .read(codingProjectsNotifierProvider)
          .projects
          .single;
      expect(reloadedProject.id, project.id);
      expect(reloadedProject.rootPath, projectPath);
      expect(reloadedProject.securityScopedBookmark, isNull);
    },
  );

  test(
    'ensureTerminalProject does not select an unpersisted project',
    () async {
      final failingContainer = ProviderContainer(
        overrides: [
          codingProjectRepositoryProvider.overrideWithValue(
            _FailingCodingProjectRepository(),
          ),
          securityScopedBookmarkServiceProvider.overrideWithValue(
            bookmarkService,
          ),
        ],
      );
      addTearDown(failingContainer.dispose);

      await expectLater(
        failingContainer
            .read(codingProjectsNotifierProvider.notifier)
            .ensureTerminalProject('/tmp/unpersisted-project'),
        throwsA(isA<FileSystemException>()),
      );

      final state = failingContainer.read(codingProjectsNotifierProvider);
      expect(state.projects, isEmpty);
      expect(state.selectedProject, isNull);
    },
  );

  test('re-adding a project refreshes its bookmark', () async {
    const projectPath = '/Users/test/Documents/sample_project';
    bookmarkService.createdBookmarks[projectPath] = 'bookmark-1';

    final notifier = container.read(codingProjectsNotifierProvider.notifier);
    final first = await notifier.addProject(projectPath);
    expect(first!.securityScopedBookmark, 'bookmark-1');

    bookmarkService.createdBookmarks[projectPath] = 'bookmark-2';
    final updated = await notifier.addProject(projectPath);

    expect(updated, isNotNull);
    expect(updated!.id, first.id);
    expect(updated.securityScopedBookmark, 'bookmark-2');
    final state = container.read(codingProjectsNotifierProvider);
    expect(state.projects.single.securityScopedBookmark, 'bookmark-2');
  });

  test('ensureProjectAccess persists refreshed bookmarks', () async {
    const projectPath = '/Users/test/Documents/sample_project';
    bookmarkService.createdBookmarks[projectPath] = 'bookmark-1';
    bookmarkService.accessResults['bookmark-1'] =
        const SecurityScopedBookmarkAccessResult.success(
          resolvedPath: projectPath,
          refreshedBookmark: 'bookmark-1b',
        );

    final notifier = container.read(codingProjectsNotifierProvider.notifier);
    final project = await notifier.addProject(projectPath);
    expect(project, isNotNull);

    final restored = await notifier.ensureProjectAccess(project!.id);

    expect(restored, isTrue);
    final state = container.read(codingProjectsNotifierProvider);
    expect(state.projects.single.securityScopedBookmark, 'bookmark-1b');
  });
}
