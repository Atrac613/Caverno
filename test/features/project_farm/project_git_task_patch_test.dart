import 'dart:io';

import 'package:caverno/features/project_farm/data/project_git_status_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  Future<void> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: root.path);
    expect(result.exitCode, 0, reason: result.stderr as String?);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('task-patch-');
    await git(['init', '-q']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'test']);
    await File('${root.path}/watcher.py').writeAsString('print(x)\n');
    await git(['add', 'watcher.py']);
    await git(['commit', '-qm', 'init']);
  });
  tearDown(() => root.delete(recursive: true));

  test('reads the net change of only the task files', () async {
    await File('${root.path}/watcher.py').writeAsString('logger.info(x)\n');
    await File('${root.path}/LOGGING.md').writeAsString('# Logging\n');
    await File('${root.path}/watcher.log').writeAsString('runtime output\n');

    final files = await const ProjectGitStatusReader().readTaskPatch(
      root.path,
      ['${root.path}/watcher.py', '${root.path}/LOGGING.md'],
    );

    expect(files!.map((file) => file.filePath), ['watcher.py', 'LOGGING.md']);
    expect(files.first.unifiedPatch, contains('+logger.info(x)'));
    expect(files.last.isUntracked, isTrue);
    expect(files.last.unifiedPatch, contains('+# Logging'));
  });

  test('returns no patch outside a git work tree', () async {
    final outside = await Directory.systemTemp.createTemp('no-git-');
    addTearDown(() => outside.delete(recursive: true));

    expect(
      await const ProjectGitStatusReader().readTaskPatch(outside.path, [
        '${outside.path}/a.py',
      ]),
      isNull,
    );
  });
}
