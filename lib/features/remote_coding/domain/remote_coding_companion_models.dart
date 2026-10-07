class RemoteCodingCompanionSnapshot {
  const RemoteCodingCompanionSnapshot({
    this.projectRootPath = '',
    this.worktreePath = '',
    this.tasks = const <RemoteCodingCompanionTask>[],
    this.changes = const <RemoteCodingCompanionChange>[],
    this.openQuestions = const <String>[],
    this.sourceLocators = const <String>[],
  });

  final String projectRootPath;
  final String worktreePath;
  final List<RemoteCodingCompanionTask> tasks;
  final List<RemoteCodingCompanionChange> changes;
  final List<String> openQuestions;
  final List<String> sourceLocators;

  int get completedTaskCount =>
      tasks.where((task) => task.status == 'completed').length;

  factory RemoteCodingCompanionSnapshot.fromJson(Map<String, dynamic> json) {
    final tasks = (json['tasks'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RemoteCodingCompanionTask.fromJson)
        .where((task) => task.title.isNotEmpty)
        .toList(growable: false);
    final changes = (json['changes'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(RemoteCodingCompanionChange.fromJson)
        .where((change) => change.hasChanges)
        .toList(growable: false);
    return RemoteCodingCompanionSnapshot(
      projectRootPath: _stringValue(json['projectRootPath']),
      worktreePath: _stringValue(json['worktreePath']),
      tasks: tasks,
      changes: changes,
      openQuestions: _stringList(json['openQuestions']),
      sourceLocators: _stringList(json['sourceLocators']),
    );
  }

  Map<String, dynamic> toJson() => {
    'projectRootPath': projectRootPath,
    'worktreePath': worktreePath,
    'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
    'changes': changes.map((change) => change.toJson()).toList(growable: false),
    'openQuestions': openQuestions,
    'sourceLocators': sourceLocators,
  };
}

class RemoteCodingCompanionTask {
  const RemoteCodingCompanionTask({
    required this.id,
    required this.title,
    required this.status,
    this.targetFiles = const <String>[],
  });

  final String id;
  final String title;
  final String status;
  final List<String> targetFiles;

  factory RemoteCodingCompanionTask.fromJson(Map<String, dynamic> json) {
    return RemoteCodingCompanionTask(
      id: _stringValue(json['id']),
      title: _stringValue(json['title']),
      status: _stringValue(json['status'], fallback: 'pending'),
      targetFiles: _stringList(json['targetFiles']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status,
    'targetFiles': targetFiles,
  };
}

class RemoteCodingCompanionChange {
  const RemoteCodingCompanionChange({
    required this.title,
    required this.filesChanged,
    required this.linesAdded,
    required this.linesRemoved,
    this.filePaths = const <String>[],
  });

  final String title;
  final int filesChanged;
  final int linesAdded;
  final int linesRemoved;
  final List<String> filePaths;

  bool get hasChanges =>
      filesChanged > 0 ||
      linesAdded > 0 ||
      linesRemoved > 0 ||
      filePaths.isNotEmpty;

  factory RemoteCodingCompanionChange.fromJson(Map<String, dynamic> json) {
    return RemoteCodingCompanionChange(
      title: _stringValue(json['title'], fallback: 'Assistant turn'),
      filesChanged: _intValue(json['filesChanged']),
      linesAdded: _intValue(json['linesAdded']),
      linesRemoved: _intValue(json['linesRemoved']),
      filePaths: _stringList(json['filePaths']),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'filesChanged': filesChanged,
    'linesAdded': linesAdded,
    'linesRemoved': linesRemoved,
    'filePaths': filePaths,
  };
}

String _stringValue(Object? value, {String fallback = ''}) {
  final normalized = value is String ? value.trim() : '';
  return normalized.isEmpty ? fallback : normalized;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _intValue(Object? value) => value is num ? value.toInt() : 0;
