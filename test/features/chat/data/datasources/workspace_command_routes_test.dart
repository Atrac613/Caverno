import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/local_command_workspace_containment.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/data/datasources/workspace_command_environment.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final supported =
      Platform.isMacOS &&
      File(LocalCommandWorkspaceContainment.executable).existsSync();

  test(
    'drops credentials and shell startup injection from the environment',
    () {
      final environment = WorkspaceCommandEnvironment.isolated(
        source: {
          'PATH': '/usr/bin:/bin',
          'LANG': 'en_US.UTF-8',
          'HOME': '/personal',
          'API_KEY': 'DUMMY_KEY',
          'AWS_SESSION_TOKEN': 'DUMMY_TOKEN',
          'BASH_ENV': '/personal/startup.sh',
          'PYTHONPATH': '/personal/modules',
          'DYLD_INSERT_LIBRARIES': '/personal/inject.dylib',
        },
        scratch: '/scratch',
      );
      expect(environment['PATH'], '/usr/bin:/bin');
      expect(environment['HOME'], '/scratch');
      expect(environment['TMPDIR'], '/scratch');
      for (final name in [
        'API_KEY',
        'AWS_SESSION_TOKEN',
        'BASH_ENV',
        'PYTHONPATH',
        'DYLD_INSERT_LIBRARIES',
      ]) {
        expect(environment.containsKey(name), isFalse, reason: name);
      }
    },
  );

  group('native workspace routes', () {
    late Directory fixture, project, outside;
    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('workspace-routes-');
      project = await Directory('${fixture.path}/project').create();
      outside = await Directory('${fixture.path}/outside').create();
      await File('${outside.path}/secret.txt').writeAsString('DUMMY_SECRET');
      await File('${project.path}/probe.py').writeAsString('''
from pathlib import Path
Path('inside.txt').write_text('ok')
outside = Path.cwd().parent / 'outside'
try:
    (outside / 'escape.txt').write_text('bad')
except PermissionError:
    print('write denied')
else:
    raise RuntimeError('outside write escaped')
try:
    print((outside / 'secret.txt').read_text())
except PermissionError:
    print('read denied')
else:
    raise RuntimeError('outside read escaped')
''');
    });
    tearDown(() => fixture.delete(recursive: true));

    test('managed background jobs inherit the enforced boundary', () async {
      final tools = BackgroundProcessTools();
      addTearDown(tools.dispose);
      final owner = ChatTurnOwner(
        conversationId: 'test',
        interactionGeneration: 1,
      );
      final started =
          jsonDecode(
                (await tools.startExecution(
                  owner: owner,
                  command: 'python3 probe.py',
                  workingDirectory: project.path,
                  containmentRoot: project.path,
                )).result,
              )
              as Map<String, dynamic>;
      expect(started['ok'], isTrue);
      final waited =
          jsonDecode(
                (await tools.waitExecution(
                  owner: owner,
                  jobId: started['job_id'] as String,
                  waitMs: 15000,
                )).result,
              )
              as Map<String, dynamic>;
      expect(waited['workspace_command_containment'], isTrue);
      expect(waited['exit_code'], 0, reason: '${waited['stderr_tail']}');
      expect(waited['stdout_tail'], contains('write denied\nread denied'));
      expect(File('${outside.path}/escape.txt').existsSync(), isFalse);
    });

    test(
      'Farm verification runs project code inside the same boundary',
      () async {
        final result = await const WorktreeAgentVerificationRunner().run(
          verificationCommand: 'python3 probe.py',
          worktreePath: project.path,
        );
        expect(result.verifiedGreen, isTrue, reason: result.summary);
        expect(result.output?.stdout, contains('write denied\nread denied'));
        expect(File('${outside.path}/escape.txt').existsSync(), isFalse);
      },
    );

    test('cannot signal an unrelated host process', () async {
      final target = await Process.start('/bin/sleep', ['20']);
      addTearDown(() async {
        target.kill();
        await target.exitCode;
      });
      await File('${project.path}/host_signal_probe.py').writeAsString(
        'import os, signal\nos.kill(${target.pid}, signal.SIGTERM)\n',
      );
      final result = await LocalShellTools.executeResult(
        command: 'python3 host_signal_probe.py',
        workingDirectory: project.path,
        projectRoot: project.path,
        containmentRoot: project.path,
      );
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload['exit_code'], isNot(0));
      expect(payload['stderr'], contains('Operation not permitted'));
    });
  }, skip: !supported);
}
