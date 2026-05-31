import 'dart:convert';
import 'dart:io';

import '../integration_test/test_support/remote_coding_p1_release_gate.dart';

Future<void> main(List<String> args) async {
  late final _Args parsed;
  try {
    parsed = _parseArgs(args);
  } on UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (parsed.showHelp) {
    stdout.writeln(_usage);
    return;
  }

  final root = Directory(parsed.rootPath ?? Directory.current.path);
  final templatePath = parsed.templatePath;
  if (templatePath != null) {
    final templateFile = File(templatePath);
    await templateFile.parent.create(recursive: true);
    await templateFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(remoteCodingP1ManualChecklistTemplate()),
    );
    stdout.writeln(
      'Remote Coding P1 checklist template written to $templatePath',
    );
  }

  final result = buildRemoteCodingP1ReleaseGate(
    repoRoot: root,
    manualChecklistFile: parsed.manualChecklistPath == null
        ? null
        : File(parsed.manualChecklistPath!),
    supportPacketFiles: parsed.supportPacketPaths.map(File.new).toList(),
  );

  final jsonText = const JsonEncoder.withIndent('  ').convert(result.toJson());
  final outJson = parsed.outJsonPath;
  if (outJson == null) {
    stdout.writeln(jsonText);
  } else {
    final file = File(outJson);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonText);
    stdout.writeln('Remote Coding P1 release gate JSON written to $outJson');
  }

  final outMarkdown = parsed.outMarkdownPath;
  if (outMarkdown != null) {
    final file = File(outMarkdown);
    await file.parent.create(recursive: true);
    await file.writeAsString(result.toMarkdown());
    stdout.writeln(
      'Remote Coding P1 release gate Markdown written to $outMarkdown',
    );
  }

  if (result.blockedGateIds.isNotEmpty) {
    stderr.writeln(
      'Remote Coding P1 release gate blocked: ${result.blockedGateIds.join(', ')}',
    );
    exitCode = 1;
  }
}

class _Args {
  const _Args({
    this.rootPath,
    this.manualChecklistPath,
    this.supportPacketPaths = const <String>[],
    this.templatePath,
    this.outJsonPath,
    this.outMarkdownPath,
    this.showHelp = false,
  });

  final String? rootPath;
  final String? manualChecklistPath;
  final List<String> supportPacketPaths;
  final String? templatePath;
  final String? outJsonPath;
  final String? outMarkdownPath;
  final bool showHelp;
}

_Args _parseArgs(List<String> args) {
  String? rootPath;
  String? manualChecklistPath;
  final supportPacketPaths = <String>[];
  String? templatePath;
  String? outJsonPath;
  String? outMarkdownPath;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
      case '--help':
      case '-h':
        return const _Args(showHelp: true);
      case '--root':
        rootPath = _readValue(args, ++index, arg);
      case '--manual-checklist':
        manualChecklistPath = _readValue(args, ++index, arg);
      case '--support-packet':
        supportPacketPaths.add(_readValue(args, ++index, arg));
      case '--write-template':
        templatePath = _readValue(args, ++index, arg);
      case '--out-json':
        outJsonPath = _readValue(args, ++index, arg);
      case '--out-md':
        outMarkdownPath = _readValue(args, ++index, arg);
      default:
        throw UsageException('Unknown argument: $arg');
    }
  }

  return _Args(
    rootPath: rootPath,
    manualChecklistPath: manualChecklistPath,
    supportPacketPaths: supportPacketPaths,
    templatePath: templatePath,
    outJsonPath: outJsonPath,
    outMarkdownPath: outMarkdownPath,
  );
}

String _readValue(List<String> args, int index, String option) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw UsageException('$option requires a value.');
  }
  return args[index];
}

class UsageException implements Exception {
  const UsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _usage = '''
Usage: dart run tool/remote_coding_p1_release_gate.dart [options]

Options:
  --root <path>              Repository root. Defaults to the current directory.
  --manual-checklist <path>  User-operated P1 checklist JSON.
  --support-packet <path>    Merge a copied P1 support packet checklist patch. Repeatable.
  --write-template <path>    Write a checklist template JSON.
  --out-json <path>          Write the gate report as JSON.
  --out-md <path>            Write the gate report as Markdown.
  --help                     Print this help.
''';
