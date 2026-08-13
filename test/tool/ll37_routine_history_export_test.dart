import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll37_routine_history_export.dart';
import '../../tool/ll37_verifier_fidelity_probe.dart';

void main() {
  test('exports a neutral recorded Routine pair for the LL37 probe', () async {
    final output = await Directory.systemTemp.createTemp(
      'caverno_ll37_routine_parent_',
    );
    addTearDown(() => output.delete(recursive: true));
    final evidenceDirectory = Directory('${output.path}/evidence');

    final result = await exportLl37RoutineHistoryEvidence(
      routinesFile: File(_fixturePath('routines.json')),
      selectionFile: File(_fixturePath('selection.json')),
      outputDirectory: evidenceDirectory,
      generatedAt: DateTime.utc(2026, 8, 10),
    );

    expect(result.pairId, 'routine-fixture-pair');
    expect(result.sourceSurface, 'routine');
    expect(result.casePaths, hasLength(2));
    final candidateA = await Ll37VerifierFidelityCase.load(
      File(result.casePaths[0]),
    );
    final candidateB = await Ll37VerifierFidelityCase.load(
      File(result.casePaths[1]),
    );
    expect(candidateA.caseId, endsWith('candidate-a'));
    expect(candidateB.caseId, endsWith('candidate-b'));
    expect(candidateA.changedFiles.single['path'], 'state.json');
    expect(candidateA.changedFiles.single['content'], contains('device-002'));
    expect(jsonEncode(candidateA.changedFiles), isNot(contains('192.168.')));
    expect(candidateB.changedFiles, isEmpty);
    expect(candidateA.sourceSurface, Ll37SourceSurface.routine);
    expect(candidateA.schemaVersion, 2);
    expect(candidateB.schemaVersion, 2);
    expect(candidateA.mechanicalVerificationPassed, isTrue);
    expect(candidateB.mechanicalVerificationPassed, isTrue);
    expect(candidateA.isEligible, isTrue);
    expect(candidateB.isEligible, isTrue);

    final candidateAJson =
        jsonDecode(await File(result.casePaths[0]).readAsString())
            as Map<String, dynamic>;
    final evidence = candidateAJson['verificationEvidence'] as List<dynamic>;
    expect(candidateAJson['mechanicalVerificationPassed'], isTrue);
    expect(jsonEncode(evidence), contains('dart tool/verify.dart'));
    expect(jsonEncode(evidence), contains('syntax verification passed'));
    expect(jsonEncode(evidence), isNot(contains('Hidden reasoning')));
    expect(jsonEncode(evidence), contains('State saved'));
    expect(jsonEncode(evidence), isNot(contains('192.168.')));
    expect(jsonEncode(evidence), isNot(contains('aa:bb:cc:dd:ee:ff')));
    expect(jsonEncode(evidence), contains('<redacted-mac>'));
    final manifest =
        jsonDecode(
              await File(
                '${evidenceDirectory.path}/candidate-a_manifest.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(
      (manifest['consent'] as Map<String, dynamic>)['explicitUserConsent'],
      isTrue,
    );
    final manifestTask = manifest['task'] as Map<String, dynamic>;
    expect(manifestTask['verificationCommand'], 'dart tool/verify.dart');
    expect(manifestTask['verificationResult'], 'passed');
    final brokenManifest =
        jsonDecode(
              await File(
                '${evidenceDirectory.path}/candidate-b_manifest.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(
      (brokenManifest['task'] as Map<String, dynamic>)['verificationResult'],
      'passed',
    );
    final privacy = manifest['privacy'] as Map<String, dynamic>;
    expect(privacy['localOnly'], isTrue);
    expect(privacy['anonymization'], 'network_identifiers');
    expect(jsonEncode(manifest), isNot(contains('192.168.')));
    expect(jsonEncode(manifest), contains('device-001'));

    final exportedPayload =
        (await evidenceDirectory
                .list()
                .where((entity) => entity is File)
                .cast<File>()
                .asyncMap((file) => file.readAsString())
                .toList())
            .join('\n');
    expect(exportedPayload, isNot(contains('192.168.')));
    expect(exportedPayload, isNot(contains('aa:bb:cc:dd:ee:ff')));
  });

  test('requires explicit personal-eval consent', () async {
    final directory = await _mutableFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final selectionFile = File('${directory.path}/selection.json');
    final selection =
        jsonDecode(await selectionFile.readAsString()) as Map<String, dynamic>;
    final consent = selection['consent'] as Map<String, dynamic>;
    consent['explicitUserConsent'] = false;
    await selectionFile.writeAsString(jsonEncode(selection));

    await expectLater(
      exportLl37RoutineHistoryEvidence(
        routinesFile: File('${directory.path}/routines.json'),
        selectionFile: selectionFile,
        outputDirectory: Directory('${directory.path}/evidence'),
      ),
      throwsFormatException,
    );
    expect(Directory('${directory.path}/evidence').existsSync(), isFalse);
  });

  test('rejects attended or explicit-failure source runs', () async {
    final directory = await _mutableFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final routinesFile = File('${directory.path}/routines.json');
    final routines =
        jsonDecode(await routinesFile.readAsString()) as List<dynamic>;
    final routine = routines.single as Map<String, dynamic>;
    final runs = routine['runs'] as List<dynamic>;
    final candidateA = runs.first as Map<String, dynamic>;
    candidateA['trigger'] = 'manual';
    await routinesFile.writeAsString(jsonEncode(routines));

    await expectLater(_exportMutable(directory), throwsFormatException);

    candidateA['trigger'] = 'scheduled';
    candidateA['status'] = 'failed';
    await routinesFile.writeAsString(jsonEncode(routines));
    await expectLater(_exportMutable(directory), throwsFormatException);
  });

  test('requires the pair to differ on objective tool coverage', () async {
    final directory = await _mutableFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final routinesFile = File('${directory.path}/routines.json');
    final routines =
        jsonDecode(await routinesFile.readAsString()) as List<dynamic>;
    final routine = routines.single as Map<String, dynamic>;
    final runs = routine['runs'] as List<dynamic>;
    final candidateB = runs.last as Map<String, dynamic>;
    final candidateAToolCalls =
        (runs.first as Map<String, dynamic>)['toolCalls'] as List<dynamic>;
    candidateB['toolCalls'] = candidateAToolCalls;
    await routinesFile.writeAsString(jsonEncode(routines));

    await expectLater(_exportMutable(directory), throwsFormatException);
  });

  test('requires both arms to pass the same mechanical command', () async {
    final directory = await _mutableFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final routinesFile = File('${directory.path}/routines.json');
    final routines =
        jsonDecode(await routinesFile.readAsString()) as List<dynamic>;
    final runs =
        (routines.single as Map<String, dynamic>)['runs'] as List<dynamic>;
    final candidateB = runs.last as Map<String, dynamic>;
    final verification =
        candidateB['mechanicalVerification'] as Map<String, dynamic>;

    verification['exitCode'] = 1;
    await routinesFile.writeAsString(jsonEncode(routines));
    await expectLater(_exportMutable(directory), throwsFormatException);

    verification['exitCode'] = 0;
    verification['command'] = 'dart tool/other_verify.dart';
    await routinesFile.writeAsString(jsonEncode(routines));
    await expectLater(_exportMutable(directory), throwsFormatException);

    candidateB.remove('mechanicalVerification');
    await routinesFile.writeAsString(jsonEncode(routines));
    await expectLater(_exportMutable(directory), throwsFormatException);
  });

  test('normalizes contained paths and rejects workspace escapes', () async {
    final directory = await _mutableFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    final routinesFile = File('${directory.path}/routines.json');
    final routines =
        jsonDecode(await routinesFile.readAsString()) as List<dynamic>;
    final routine = routines.single as Map<String, dynamic>;
    final runs = routine['runs'] as List<dynamic>;
    final candidateA = runs.first as Map<String, dynamic>;
    final toolCalls = candidateA['toolCalls'] as List<dynamic>;
    final writeCall =
        toolCalls.firstWhere(
              (item) => (item as Map<String, dynamic>)['name'] == 'write_file',
            )
            as Map<String, dynamic>;
    final arguments =
        jsonDecode(writeCall['arguments'] as String) as Map<String, dynamic>;
    arguments['path'] = '/tmp/fixture/nested/state.json';
    writeCall['arguments'] = jsonEncode(arguments);
    await routinesFile.writeAsString(jsonEncode(routines));

    final result = await _exportMutable(directory);
    final candidate = await Ll37VerifierFidelityCase.load(
      File(result.casePaths.first),
    );
    expect(candidate.changedFiles.single['path'], 'nested/state.json');
    final payload = await File(result.casePaths.first).readAsString();
    expect(payload, isNot(contains('/tmp/fixture')));

    await Directory('${directory.path}/evidence').delete(recursive: true);
    arguments['path'] = '/tmp/outside/state.json';
    writeCall['arguments'] = jsonEncode(arguments);
    await routinesFile.writeAsString(jsonEncode(routines));
    await expectLater(_exportMutable(directory), throwsFormatException);
  });

  test('refuses to replace an existing evidence directory', () async {
    final directory = await _mutableFixtureDirectory();
    addTearDown(() => directory.delete(recursive: true));
    await Directory('${directory.path}/evidence').create();

    await expectLater(
      _exportMutable(directory),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('parses required CLI paths', () {
    final options = Ll37RoutineHistoryExportOptions.parse(const [
      '--routines-json',
      'routines.json',
      '--selection',
      'selection.json',
      '--out-dir',
      'evidence',
    ]);

    expect(options.routinesPath, 'routines.json');
    expect(options.selectionPath, 'selection.json');
    expect(options.outputDirectoryPath, 'evidence');
    expect(
      () => Ll37RoutineHistoryExportOptions.parse(const ['--routines-json']),
      throwsFormatException,
    );
  });
}

Future<Directory> _mutableFixtureDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'caverno_ll37_routine_fixture_',
  );
  await File(
    '${directory.path}/routines.json',
  ).writeAsString(await File(_fixturePath('routines.json')).readAsString());
  await File(
    '${directory.path}/selection.json',
  ).writeAsString(await File(_fixturePath('selection.json')).readAsString());
  return directory;
}

Future<Ll37RoutineHistoryExportResult> _exportMutable(Directory directory) {
  return exportLl37RoutineHistoryEvidence(
    routinesFile: File('${directory.path}/routines.json'),
    selectionFile: File('${directory.path}/selection.json'),
    outputDirectory: Directory('${directory.path}/evidence'),
  );
}

String _fixturePath(String name) {
  return '${Directory.current.path}/tool/fixtures/'
      'll37_routine_history/$name';
}
