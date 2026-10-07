import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A widget file that nothing imports is a screen nobody can reach.
///
/// **The analyzer cannot report this.** `unused_element` covers *private*
/// declarations, so a public widget class alone in its file, imported by
/// nothing, is invisible to `flutter analyze`. That is exactly the state
/// `plan_open_question_section.dart` and `contract_item_list_section.dart` were
/// in: their one mount, `_buildWorkflowPanel`, lost its call site on
/// 2026-04-18 and was deleted on 2026-09-20, and the tree stayed green for
/// five months. Their own widget tests passed the whole time, because a widget
/// test mounts what it is handed and asks nothing about who else does.
///
/// Scope is widgets rather than all of `lib/` on purpose. A service with no
/// caller is usually caught by `unused_element` or by a boundary test; a widget
/// is the thing a person either sees or does not, and the cost of not seeing it
/// is a feature that reads as shipped and is not.
///
/// This checks *direct* reachability. A chain — an orphan whose only importer
/// is itself an orphan — surfaces one layer per run, the same way the
/// analyzer's own cascade does: delete what this names, run it again, and the
/// next layer appears.
///
/// Matching is by file name, which is sound only while file names are unique
/// across `lib/`. The test asserts that first, so the day it stops being true
/// this fails loudly rather than quietly missing an importer.
const Map<String, String> _allowedOrphans = <String, String>{
  // 'lib/.../some_widget.dart': 'why a file nobody imports is still built',
  //
  // Deliberately empty. An entry here is a claim that a widget worth compiling
  // is worth compiling with no way to reach it, which is a claim that should
  // have to be written down.
};

const String _widgetDirectorySegment = '/presentation/widgets/';

void main() {
  final libraryFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path)
      .where((path) => path.endsWith('.dart'))
      .toList(growable: false)
    ..sort();

  test('every file name under lib/ is unique', () {
    // The reachability check below matches directives by file name. Two files
    // sharing one would let either stand in for the other, so an orphan could
    // pass on its twin's importer.
    final byName = <String, List<String>>{};
    for (final path in libraryFiles) {
      byName.putIfAbsent(path.split('/').last, () => <String>[]).add(path);
    }
    final collisions = byName.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
        .toList(growable: false);
    expect(
      collisions,
      isEmpty,
      reason:
          'Reachability is matched by file name; these share one, so the check '
          'below can no longer tell them apart. Rename one, or teach the check '
          'to resolve import URIs against the importing file.',
    );
  });

  test('every widget file is imported by something in lib/', () {
    final contents = <String, String>{
      for (final path in libraryFiles) path: File(path).readAsStringSync(),
    };
    final widgetFiles = libraryFiles
        .where((path) => path.contains(_widgetDirectorySegment))
        .toList(growable: false);
    expect(
      widgetFiles,
      isNotEmpty,
      reason:
          'No widget files were found, so this check is measuring nothing. The '
          'directory layout moved; update $_widgetDirectorySegment.',
    );

    final orphans = <String>[];
    for (final path in widgetFiles) {
      final name = path.split('/').last.replaceAll('.', r'\.');
      // `part` counts: a file pulled into a library is reachable through it.
      final directive = RegExp(
        '''^\\s*(?:import|export|part)\\s+['"][^'"]*$name['"]''',
        multiLine: true,
      );
      final imported = contents.entries.any(
        (entry) => entry.key != path && directive.hasMatch(entry.value),
      );
      if (!imported && !_allowedOrphans.containsKey(path)) {
        orphans.add(path);
      }
    }

    expect(
      orphans,
      isEmpty,
      reason:
          'These widget files are imported by nothing in lib/, so nothing can '
          'render them. Delete them with the tests and ratchet rows that name '
          'them, or add an entry to _allowedOrphans saying why a widget with '
          'no way in is still worth building. A widget test passing is not an '
          'answer: it mounts what it is handed.\n'
          '${orphans.join('\n')}',
    );
  });
}
