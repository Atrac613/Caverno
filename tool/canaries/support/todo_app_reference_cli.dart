// A known-good todo_app.md implementation, copied into the fixture workspace as
// `bin/todo_cli.dart` by scenarios that gate on auto-continuation rather than on
// code generation.
//
// It is a real Dart file rather than a string constant so that `dart analyze`
// and `dart format` cover it. A seeded fixture that no longer compiles would
// reproduce the failure this file exists to remove, and would do so silently.
//
// Keep it inside todo_app.md's scope: no due dates, priorities, or tags. The
// fixture's acceptance criteria include "no feature outside the scope list was
// added", so growing this file breaks the very check it is meant to satisfy.
import 'dart:convert';
import 'dart:io';

const _stateFileName = 'todo_tasks.json';

const _usage = '''
Usage: todo_cli <command> [arguments]

Commands:
  add <text>     Add a task
  list           Show every task
  done <id>      Mark a task complete
  delete <id>    Remove a task
  help           Show this message
''';

class _Task {
  const _Task({required this.id, required this.text, required this.done});

  factory _Task.fromJson(Map<String, dynamic> json) => _Task(
    id: json['id'] as int,
    text: json['text'] as String,
    done: json['done'] as bool? ?? false,
  );

  final int id;
  final String text;
  final bool done;

  _Task completed() => _Task(id: id, text: text, done: true);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
}

File _stateFile() => File(_stateFileName);

/// A missing or unreadable state file is an empty list, not a crash. This is
/// the first-run criterion, and treating a parse failure the same way keeps a
/// truncated file from becoming a stack trace.
List<_Task> _load() {
  final file = _stateFile();
  if (!file.existsSync()) {
    return <_Task>[];
  }
  final contents = file.readAsStringSync().trim();
  if (contents.isEmpty) {
    return <_Task>[];
  }
  try {
    final decoded = jsonDecode(contents);
    if (decoded is! List) {
      return <_Task>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_Task.fromJson)
        .toList();
  } on FormatException {
    return <_Task>[];
  }
}

void _save(List<_Task> tasks) {
  _stateFile().writeAsStringSync(
    '${jsonEncode(tasks.map((task) => task.toJson()).toList())}\n',
  );
}

/// Ids never reuse a deleted value, so an id captured before a delete still
/// refers to the same task afterwards.
int _nextId(List<_Task> tasks) =>
    tasks.fold<int>(
      0,
      (highest, task) => task.id > highest ? task.id : highest,
    ) +
    1;

int _add(List<String> arguments) {
  final text = arguments.join(' ').trim();
  if (text.isEmpty) {
    stderr.writeln('add needs the task text, for example: add "buy milk"');
    return 1;
  }
  final tasks = _load();
  final task = _Task(id: _nextId(tasks), text: text, done: false);
  _save([...tasks, task]);
  // The id comes first so a caller can read it back without guessing.
  stdout.writeln('Added ${task.id}: ${task.text}');
  return 0;
}

int _list() {
  final tasks = _load();
  if (tasks.isEmpty) {
    stdout.writeln('No tasks yet. Add one with: add <text>');
    return 0;
  }
  for (final task in tasks) {
    stdout.writeln('${task.done ? '[x]' : '[ ]'} ${task.id} ${task.text}');
  }
  return 0;
}

int _done(List<String> arguments) {
  final id = _parseId(arguments, 'done');
  if (id == null) {
    return 1;
  }
  final tasks = _load();
  if (!tasks.any((task) => task.id == id)) {
    stderr.writeln('No task with id $id.');
    return 1;
  }
  _save([for (final task in tasks) task.id == id ? task.completed() : task]);
  stdout.writeln('Completed $id.');
  return 0;
}

int _delete(List<String> arguments) {
  final id = _parseId(arguments, 'delete');
  if (id == null) {
    return 1;
  }
  final tasks = _load();
  if (!tasks.any((task) => task.id == id)) {
    stderr.writeln('No task with id $id.');
    return 1;
  }
  _save(tasks.where((task) => task.id != id).toList());
  stdout.writeln('Deleted $id.');
  return 0;
}

int? _parseId(List<String> arguments, String command) {
  if (arguments.isEmpty) {
    stderr.writeln('$command needs a task id, for example: $command 1');
    return null;
  }
  final id = int.tryParse(arguments.first);
  if (id == null) {
    stderr.writeln('"${arguments.first}" is not a task id.');
    return null;
  }
  return id;
}

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stdout.write(_usage);
    return;
  }
  final command = arguments.first;
  final rest = arguments.skip(1).toList();
  final status = switch (command) {
    'add' => _add(rest),
    'list' => _list(),
    'done' => _done(rest),
    'delete' => _delete(rest),
    'help' || '--help' || '-h' => () {
      stdout.write(_usage);
      return 0;
    }(),
    _ => () {
      stderr.writeln('Unknown command "$command".');
      stdout.write(_usage);
      return 1;
    }(),
  };
  if (status != 0) {
    exitCode = status;
  }
}
