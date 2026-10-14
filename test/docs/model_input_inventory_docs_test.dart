import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LL46: every session-log request label a producer in `lib/` can emit must
/// have a row in `docs/model_input_inventory.md`, so a new injection cannot
/// ship without its producer, shape and prefix effect written down.
void main() {
  test('every request label has an inventory row', () {
    final inventory = File('docs/model_input_inventory.md').readAsStringSync();
    final documented = RegExp(
      r'^\| `([^`]+)` \|',
      multiLine: true,
    ).allMatches(inventory).map((match) => match.group(1)!).toSet();

    final labels = _labelsInLib();
    expect(labels, isNotEmpty);
    expect(
      labels.difference(documented),
      isEmpty,
      reason: 'Add a row to docs/model_input_inventory.md for each label.',
    );
  });
}

/// Label literals, by the patterns their producers use.
Set<String> _labelsInLib() {
  final generic = [
    RegExp(r"(?:requestLabel|logLabel)\s*:\s*'([^']+)'"),
    RegExp(r"withRequestLabel\('([^']+)'\)"),
  ];
  final perFile = <String, RegExp>{
    'lib/features/chat/domain/services/coding/coding_recovery_text.dart':
        RegExp(r"label:\s*'([^']+)'"),
    'lib/features/chat/domain/services/tool_loop/reasoning_only_stop.dart':
        RegExp(r"static const label = '([^']+)'"),
    'lib/features/chat/data/datasources/secondary_request_label.dart': RegExp(
      r"=> '([^']+)'",
    ),
    'lib/features/chat/presentation/providers/pro_reasoning_run_notifier.dart':
        RegExp(r"operation:\s*'([^']+)'"),
  };
  final labels = <String>{};
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final source = file.readAsStringSync();
    for (final pattern in generic) {
      labels.addAll(pattern.allMatches(source).map((m) => m.group(1)!));
    }
  }
  perFile.forEach((path, pattern) {
    final source = File(path).readAsStringSync();
    final found = pattern.allMatches(source).map((m) => m.group(1)!).toList();
    expect(found, isNotEmpty, reason: '$path no longer matches its pattern');
    labels.addAll(found);
  });
  return labels;
}
