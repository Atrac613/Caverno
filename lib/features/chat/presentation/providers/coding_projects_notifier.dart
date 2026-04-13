import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/coding_project_repository.dart';
import '../../domain/entities/coding_project.dart';

class CodingProjectsState {
  const CodingProjectsState({
    required this.projects,
    required this.selectedProjectId,
    this.isLoading = false,
  });

  final List<CodingProject> projects;
  final String? selectedProjectId;
  final bool isLoading;

  factory CodingProjectsState.initial() =>
      const CodingProjectsState(projects: [], selectedProjectId: null);

  CodingProjectsState copyWith({
    List<CodingProject>? projects,
    String? selectedProjectId,
    bool? isLoading,
    bool clearSelectedProject = false,
  }) {
    return CodingProjectsState(
      projects: projects ?? this.projects,
      selectedProjectId: clearSelectedProject
          ? null
          : (selectedProjectId ?? this.selectedProjectId),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  CodingProject? get selectedProject => findById(selectedProjectId);

  CodingProject? findById(String? id) {
    if (id == null) return null;
    try {
      return projects.firstWhere((project) => project.id == id);
    } catch (_) {
      return null;
    }
  }
}

final codingProjectsNotifierProvider =
    NotifierProvider<CodingProjectsNotifier, CodingProjectsState>(
      CodingProjectsNotifier.new,
    );

class CodingProjectsNotifier extends Notifier<CodingProjectsState> {
  late final CodingProjectRepository _repository;
  final _uuid = const Uuid();

  @override
  CodingProjectsState build() {
    _repository = ref.read(codingProjectRepositoryProvider);
    final projects = _repository.loadAll();
    return CodingProjectsState(
      projects: projects,
      selectedProjectId: projects.isEmpty ? null : projects.first.id,
    );
  }

  void selectProject(String? id) {
    state = state.copyWith(
      selectedProjectId: id,
      clearSelectedProject: id == null,
    );
  }

  Future<CodingProject?> addProject(String rootPath) async {
    final normalizedPath = rootPath.trim();
    if (normalizedPath.isEmpty) return null;

    final existingProject = state.projects
        .where((project) => project.normalizedRootPath == normalizedPath)
        .cast<CodingProject?>()
        .firstOrNull;
    if (existingProject != null) {
      state = state.copyWith(selectedProjectId: existingProject.id);
      return existingProject;
    }

    final now = DateTime.now();
    final project = CodingProject(
      id: _uuid.v4(),
      name: _displayNameFromPath(normalizedPath),
      rootPath: normalizedPath,
      createdAt: now,
      updatedAt: now,
    );

    final projects = [project, ...state.projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(projects: projects, selectedProjectId: project.id);
    await _repository.saveAll(projects);
    return project;
  }

  Future<void> removeProject(String id) async {
    final projects = state.projects
        .where((project) => project.id != id)
        .toList();
    final nextSelectedId = state.selectedProjectId == id
        ? (projects.isEmpty ? null : projects.first.id)
        : state.selectedProjectId;

    state = state.copyWith(
      projects: projects,
      selectedProjectId: nextSelectedId,
      clearSelectedProject: nextSelectedId == null,
    );
    await _repository.saveAll(projects);
  }

  String _displayNameFromPath(String path) {
    final segments = path
        .split(RegExp(r'[\\\/]+'))
        .where((segment) => segment.isNotEmpty);
    if (segments.isEmpty) return path;
    return segments.last;
  }
}
