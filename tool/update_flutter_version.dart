import 'dart:convert';
import 'dart:io';

final _syncPatterns = <String, List<ReplacementRule>>{
  'README.md': [
    ReplacementRule(
      RegExp(
        r'Flutter \d+\.\d+\.\d+ \(managed via \[FVM\]\(https://fvm\.app/\)\)',
      ),
      (version) => 'Flutter $version (managed via [FVM](https://fvm.app/))',
    ),
  ],
  'AGENTS.md': [
    ReplacementRule(
      RegExp(r'fvm use \d+\.\d+\.\d+'),
      (version) => 'fvm use $version',
    ),
  ],
  'CLAUDE.md': [
    ReplacementRule(
      RegExp(r'fvm use \d+\.\d+\.\d+'),
      (version) => 'fvm use $version',
    ),
  ],
};

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart tool/update_flutter_version.dart <current-version> <next-version>',
    );
    exitCode = 64;
    return;
  }

  final currentVersion = args[0].trim();
  final nextVersion = args[1].trim();
  if (currentVersion.isEmpty || nextVersion.isEmpty) {
    stderr.writeln('Flutter versions must not be empty.');
    exitCode = 64;
    return;
  }

  final fvmrcFile = File('.fvmrc');
  final fvmrcData =
      jsonDecode(fvmrcFile.readAsStringSync()) as Map<String, dynamic>;
  final pinnedVersion = fvmrcData['flutter'] as String?;

  if (pinnedVersion == null || pinnedVersion.isEmpty) {
    stderr.writeln('Could not read the current Flutter version from .fvmrc.');
    exitCode = 65;
    return;
  }

  if (pinnedVersion != currentVersion && pinnedVersion != nextVersion) {
    stderr.writeln(
      'Unexpected .fvmrc version: $pinnedVersion. '
      'Expected $currentVersion or $nextVersion.',
    );
    exitCode = 65;
    return;
  }

  fvmrcData['flutter'] = nextVersion;
  const encoder = JsonEncoder.withIndent('  ');
  fvmrcFile.writeAsStringSync('${encoder.convert(fvmrcData)}\n');

  for (final entry in _syncPatterns.entries) {
    final path = entry.key;
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }

    var content = file.readAsStringSync();
    for (final rule in entry.value) {
      content = content.replaceAllMapped(
        rule.pattern,
        (_) => rule.replacement(nextVersion),
      );
    }
    file.writeAsStringSync(content);
  }
}

class ReplacementRule {
  const ReplacementRule(this.pattern, this.replacement);

  final RegExp pattern;
  final String Function(String version) replacement;
}
