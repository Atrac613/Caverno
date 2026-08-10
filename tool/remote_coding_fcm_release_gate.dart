import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/remote_coding_fcm_release_gate.dart';

Future<void> main(List<String> args) async {
  final options = _options(args);
  final templatePath = options['write-template'];
  if (templatePath != null) {
    await _write(
      templatePath,
      const JsonEncoder.withIndent(
        '  ',
      ).convert(remoteCodingFcmManualChecklistTemplate()),
    );
  }
  final result = buildRemoteCodingFcmReleaseGate(
    repoRoot: Directory(options['root'] ?? Directory.current.path),
    manualChecklistFile: options['manual-checklist'] == null
        ? null
        : File(options['manual-checklist']!),
  );
  final json = const JsonEncoder.withIndent('  ').convert(result.toJson());
  final outJson = options['out-json'];
  if (outJson == null) {
    stdout.writeln(json);
  } else {
    await _write(outJson, json);
  }
  final outMarkdown = options['out-md'];
  if (outMarkdown != null) {
    await _write(outMarkdown, result.toMarkdown());
  }
  if (result.blockedGateIds.isNotEmpty) {
    stderr.writeln(
      'Remote Coding FCM release blocked: ${result.blockedGateIds.join(', ')}',
    );
    exitCode = 1;
  }
}

Map<String, String> _options(List<String> args) {
  const names = {
    '--root': 'root',
    '--manual-checklist': 'manual-checklist',
    '--write-template': 'write-template',
    '--out-json': 'out-json',
    '--out-md': 'out-md',
  };
  final values = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    final name = names[args[index]];
    if (name == null || index + 1 >= args.length) {
      throw FormatException('Invalid FCM release gate arguments: $args');
    }
    values[name] = args[index + 1];
  }
  return values;
}

Future<void> _write(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
