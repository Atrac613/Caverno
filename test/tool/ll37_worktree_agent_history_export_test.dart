import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll37_verifier_fidelity_probe.dart';
import '../../tool/ll37_worktree_agent_history_export.dart';

void main() {
  test('exports a consented LL13 pair for the LL37 probe', () async {
    final parent = await Directory.systemTemp.createTemp(
      'caverno_ll37_worktree_export_',
    );
    addTearDown(() => parent.delete(recursive: true));
    final evidenceDirectory = Directory('${parent.path}/evidence');

    final result = await exportLl37WorktreeAgentHistoryEvidence(
      tasksFile: File(_fixturePath('tasks.json')),
      selectionFile: File(_fixturePath('selection.json')),
      outputDirectory: evidenceDirectory,
      generatedAt: DateTime.utc(2026, 8, 10),
    );

    expect(result.pairId, 'worktree-greeting-pair');
    expect(result.sourceSurface, 'worktree_agent');
    expect(result.casePaths, hasLength(2));
    final candidateA = await Ll37VerifierFidelityCase.load(
      File(result.casePaths[0]),
    );
    final candidateB = await Ll37VerifierFidelityCase.load(
      File(result.casePaths[1]),
    );
    expect(candidateA.expectedVerdict, Ll37ExpectedVerdict.notRefuted);
    expect(candidateB.expectedVerdict, Ll37ExpectedVerdict.refuted);
    expect(candidateA.sourceSurface, Ll37SourceSurface.worktreeAgent);
    expect(candidateA.schemaVersion, 2);
    expect(candidateB.schemaVersion, 2);
    expect(candidateA.mechanicalVerificationPassed, isTrue);
    expect(candidateB.mechanicalVerificationPassed, isTrue);
    expect(candidateA.isEligible, isTrue);
    expect(candidateB.isEligible, isTrue);
    expect(candidateA.objective, candidateB.objective);
    expect(candidateA.changedFiles, hasLength(2));
    expect(candidateB.changedFiles.single['path'], 'lib/greeting.dart');

    final payload = await _joinedPayload(evidenceDirectory);
    expect(payload, isNot(contains('/Users/example/private')));
    expect(payload, isNot(contains('192.168.100.241')));
    expect(payload, isNot(contains('super-secret-value')));
    expect(payload, contains('<worktree-root>'));
    expect(payload, contains('<redacted-host>'));
    expect(payload, contains('API_TOKEN=[redacted]'));
    expect(payload, contains('sourceContentHash'));
    expect(payload, contains('controlled_live_canary'));
    expect(payload, contains('mechanically green objective-miss control'));
    expect(
      RegExp(r'"verificationResult": "passed"').allMatches(payload),
      hasLength(2),
    );
    expect(
      RegExp(r'"mechanicalVerificationPassed": true').allMatches(payload),
      hasLength(2),
    );
  });

  test('requires explicit personal-eval consent', () async {
    final fixture = await _mutableFixture();
    addTearDown(() => fixture.delete(recursive: true));
    final selectionFile = File('${fixture.path}/selection.json');
    final selection =
        jsonDecode(await selectionFile.readAsString()) as Map<String, dynamic>;
    (selection['consent'] as Map<String, dynamic>)['explicitUserConsent'] =
        false;
    await selectionFile.writeAsString(jsonEncode(selection));

    await expectLater(_exportMutable(fixture), throwsFormatException);
    expect(Directory('${fixture.path}/evidence').existsSync(), isFalse);
  });

  test('requires a completed mechanically-green matched pair', () async {
    final fixture = await _mutableFixture();
    addTearDown(() => fixture.delete(recursive: true));
    final tasksFile = File('${fixture.path}/tasks.json');
    final tasks = jsonDecode(await tasksFile.readAsString()) as List<dynamic>;
    final correct = tasks.first as Map<String, dynamic>;
    correct['verifiedGreen'] = false;
    await tasksFile.writeAsString(jsonEncode(tasks));
    await expectLater(_exportMutable(fixture), throwsFormatException);

    correct['verifiedGreen'] = true;
    final broken = tasks.last as Map<String, dynamic>;
    broken['verifiedGreen'] = false;
    await tasksFile.writeAsString(jsonEncode(tasks));
    await expectLater(_exportMutable(fixture), throwsFormatException);

    broken['verifiedGreen'] = true;
    correct['status'] = 'running';
    await tasksFile.writeAsString(jsonEncode(tasks));
    await expectLater(_exportMutable(fixture), throwsFormatException);

    correct['status'] = 'completed';
    correct['prompt'] = 'A different objective.';
    await tasksFile.writeAsString(jsonEncode(tasks));
    await expectLater(_exportMutable(fixture), throwsFormatException);
  });

  test('rejects unsafe, truncated, or inconsistent file evidence', () async {
    final fixture = await _mutableFixture();
    addTearDown(() => fixture.delete(recursive: true));
    final tasksFile = File('${fixture.path}/tasks.json');
    final tasks = jsonDecode(await tasksFile.readAsString()) as List<dynamic>;
    final correct = tasks.first as Map<String, dynamic>;
    final files = correct['changedFiles'] as List<dynamic>;
    final firstFile = files.first as Map<String, dynamic>;

    firstFile['path'] = '../outside.dart';
    await tasksFile.writeAsString(jsonEncode(tasks));
    await expectLater(_exportMutable(fixture), throwsFormatException);

    firstFile['path'] = 'lib/greeting.dart';
    firstFile['truncated'] = true;
    await tasksFile.writeAsString(jsonEncode(tasks));
    await expectLater(_exportMutable(fixture), throwsFormatException);

    firstFile['truncated'] = false;
    firstFile['contentHash'] = 'bad-hash';
    await tasksFile.writeAsString(jsonEncode(tasks));
    await expectLater(_exportMutable(fixture), throwsFormatException);
  });

  test('refuses to replace an existing evidence directory', () async {
    final fixture = await _mutableFixture();
    addTearDown(() => fixture.delete(recursive: true));
    await Directory('${fixture.path}/evidence').create();

    await expectLater(
      _exportMutable(fixture),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('parses required CLI paths', () {
    final options = Ll37WorktreeAgentHistoryExportOptions.parse(const [
      '--tasks-json',
      'tasks.json',
      '--selection',
      'selection.json',
      '--out-dir',
      'evidence',
    ]);

    expect(options.tasksPath, 'tasks.json');
    expect(options.selectionPath, 'selection.json');
    expect(options.outputDirectoryPath, 'evidence');
    expect(
      () => Ll37WorktreeAgentHistoryExportOptions.parse(const ['--tasks-json']),
      throwsFormatException,
    );
  });
}

Future<Directory> _mutableFixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'caverno_ll37_worktree_fixture_',
  );
  await File(
    '${directory.path}/tasks.json',
  ).writeAsString(await File(_fixturePath('tasks.json')).readAsString());
  await File(
    '${directory.path}/selection.json',
  ).writeAsString(await File(_fixturePath('selection.json')).readAsString());
  return directory;
}

Future<Ll37WorktreeAgentHistoryExportResult> _exportMutable(
  Directory directory,
) {
  return exportLl37WorktreeAgentHistoryEvidence(
    tasksFile: File('${directory.path}/tasks.json'),
    selectionFile: File('${directory.path}/selection.json'),
    outputDirectory: Directory('${directory.path}/evidence'),
  );
}

Future<String> _joinedPayload(Directory directory) async {
  final contents = await directory
      .list()
      .where((entry) => entry is File)
      .cast<File>()
      .asyncMap((file) => file.readAsString())
      .toList();
  return contents.join('\n');
}

String _fixturePath(String name) {
  return '${Directory.current.path}/tool/fixtures/'
      'll37_worktree_agent_history/$name';
}
