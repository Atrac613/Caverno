import 'package:caverno/core/services/security_scoped_bookmark_service.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/presentation/coordinators/coding_project_picker.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedBookmarkService extends SecurityScopedBookmarkService {
  _ScriptedBookmarkService(this.pickResult);

  final DirectoryPickResult pickResult;

  @override
  Future<DirectoryPickResult> pickDirectory({String? initialDirectory}) async {
    return pickResult;
  }

  @override
  Future<String?> createBookmark(String path) async {
    fail('picker-provided bookmark should not create another bookmark');
  }
}

class _RecordingProjectsNotifier extends CodingProjectsNotifier {
  final addedPaths = <String>[];
  final addedBookmarks = <String?>[];

  @override
  CodingProjectsState build() => CodingProjectsState.initial();

  @override
  Future<CodingProject?> addProject(String rootPath, {String? bookmark}) async {
    addedPaths.add(rootPath);
    addedBookmarks.add(bookmark);
    return CodingProject(
      id: 'project-1',
      name: 'picked',
      rootPath: rootPath,
      securityScopedBookmark: bookmark,
      createdAt: DateTime(2026, 9, 6),
      updatedAt: DateTime(2026, 9, 6),
    );
  }
}

void main() {
  test('failed picks do not add a project', () async {
    final projects = _RecordingProjectsNotifier();
    final activated = <String>[];

    await pickAndActivateCodingProject(
      bookmarks: _ScriptedBookmarkService(
        const DirectoryPickResult.failed('picker_busy'),
      ),
      projects: projects,
      isMounted: () => true,
      activate: (projectId, {createFreshOnFirstOpen = false}) async {
        activated.add(projectId);
      },
    );

    expect(projects.addedPaths, isEmpty);
    expect(activated, isEmpty);
  });

  test('cancelled picks do not add a project', () async {
    final projects = _RecordingProjectsNotifier();
    final activated = <String>[];

    await pickAndActivateCodingProject(
      bookmarks: _ScriptedBookmarkService(
        const DirectoryPickResult.cancelled(),
      ),
      projects: projects,
      isMounted: () => true,
      activate: (projectId, {createFreshOnFirstOpen = false}) async {
        activated.add(projectId);
      },
    );

    expect(projects.addedPaths, isEmpty);
    expect(activated, isEmpty);
  });

  test('successful picks add and activate with the panel bookmark', () async {
    final projects = _RecordingProjectsNotifier();
    final activated = <String>[];

    await pickAndActivateCodingProject(
      bookmarks: _ScriptedBookmarkService(
        const DirectoryPickResult.picked(
          '/tmp/new-project',
          bookmark: 'panel-bookmark',
        ),
      ),
      projects: projects,
      isMounted: () => true,
      activate: (projectId, {createFreshOnFirstOpen = false}) async {
        activated.add(projectId);
      },
    );

    expect(projects.addedPaths, ['/tmp/new-project']);
    expect(projects.addedBookmarks, ['panel-bookmark']);
    expect(activated, ['project-1']);
  });

  test(
    'unmounted pages do not add a project after the picker returns',
    () async {
      final projects = _RecordingProjectsNotifier();
      final activated = <String>[];

      await pickAndActivateCodingProject(
        bookmarks: _ScriptedBookmarkService(
          const DirectoryPickResult.picked(
            '/tmp/new-project',
            bookmark: 'panel-bookmark',
          ),
        ),
        projects: projects,
        isMounted: () => false,
        activate: (projectId, {createFreshOnFirstOpen = false}) async {
          activated.add(projectId);
        },
      );

      expect(projects.addedPaths, isEmpty);
      expect(activated, isEmpty);
    },
  );
}
