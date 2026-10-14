import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LL46: every session-log request label a producer in `lib/` can emit, and
/// every file that writes guidance into a tool result, must have a row in
/// `docs/model_input_inventory.md`, so a new injection cannot ship without
/// its producer and effect written down.
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

  test('every system prompt section has an inventory row', () {
    final inventory = File('docs/model_input_inventory.md').readAsStringSync();
    final builder = File(
      'lib/features/chat/domain/services/system_prompt_builder.dart',
    ).readAsStringSync();
    final ids = RegExp(
      r"buffer\.section\('([a-z_]+)'\)",
    ).allMatches(builder).map((match) => match.group(1)!).toSet();
    expect(ids, isNotEmpty);
    expect(
      ids.where((id) => !inventory.contains('| `$id` |')),
      isEmpty,
      reason:
          'Add a row to the system prompt section table in '
          'docs/model_input_inventory.md for each section.',
    );
  });

  test('every producer of tool-result guidance has an inventory row', () {
    final inventory = File('docs/model_input_inventory.md').readAsStringSync();
    final guidance = RegExp(
      r"'(?:required_action|requiredAction|instruction|instructions)'\s*:",
    );
    final producers = <String>{
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            guidance.hasMatch(file.readAsStringSync()))
          file.path.substring('lib/'.length),
    };
    expect(producers, isNotEmpty);
    final missing = producers.where(
      (path) => !inventory.contains('| `$path` |'),
    );
    expect(
      missing,
      isEmpty,
      reason:
          'Add a row to the tool-result guidance table in '
          'docs/model_input_inventory.md for each producer.',
    );
  });
}

/// Label literals, by the patterns their producers use.
Set<String> _labelsInLib() {
  final generic = [
    RegExp(r"(?:requestLabel|logLabel)\s*:\s*'([^']+)'"),
    RegExp(r"withRequestLabel\('([^']+)'\)"),
  ];
  // Farm requests are labelled with their structured-output schema name.
  final farmSchema = RegExp(r"schemaName:\s*'([^']+)'");
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
    if (file.path.startsWith('lib/features/project_farm/')) {
      labels.addAll(farmSchema.allMatches(source).map((m) => m.group(1)!));
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
