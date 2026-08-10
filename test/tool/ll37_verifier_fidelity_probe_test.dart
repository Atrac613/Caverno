import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll37_verifier_fidelity_probe.dart';

void main() {
  final correctPath = _fixturePath('slugify_correct_case.json');
  final brokenPath = _fixturePath('slugify_broken_case.json');

  test('fixture mode scores a pair but excludes it from the gate', () async {
    final report = await runLl37VerifierFidelityProbe(
      options: Ll37VerifierFidelityProbeOptions(
        showHelp: false,
        fixtureResponse: true,
        casePaths: [correctPath, brokenPath],
        timeoutSeconds: 1,
      ),
      generatedAt: DateTime.utc(2026, 8, 10),
    );

    expect(report.gate, 'no_go_insufficient_eligible_sample');
    expect(report.allCases.totalCount, 2);
    expect(report.allCases.falseRefuteRate, 0);
    expect(report.allCases.brokenRecall, 1);
    expect(report.eligibleCases.totalCount, 0);
    expect(
      report.toJson()['schemaName'],
      'caverno_ll37_verifier_fidelity_report',
    );
    expect(report.toMarkdown(), contains('LL37 Verifier Fidelity Probe'));
  });

  test(
    'prompt omits the expected verdict and scores model responses',
    () async {
      final prompts = <Ll37VerifierPrompt>[];
      final report = await runLl37VerifierFidelityProbe(
        options: Ll37VerifierFidelityProbeOptions(
          showHelp: false,
          fixtureResponse: false,
          casePaths: [correctPath, brokenPath],
          timeoutSeconds: 1,
          baseUrl: 'http://unused.invalid/v1',
          model: 'fixture-model',
        ),
        complete: (prompt) async {
          prompts.add(prompt);
          final verdict = prompt.caseId.endsWith('correct')
              ? 'not_refuted'
              : 'refuted';
          return jsonEncode({
            'verdict': verdict,
            'confidence': 0.9,
            'findings': <Map<String, String>>[],
          });
        },
      );

      expect(prompts, hasLength(2));
      for (final prompt in prompts) {
        expect(prompt.userPrompt, isNot(contains('expectedVerdict')));
        expect(prompt.userPrompt, isNot(contains('sourceSurface')));
        expect(prompt.userPrompt, isNot(contains(prompt.caseId)));
        expect(prompt.userPrompt, isNot(contains('correct')));
        expect(prompt.userPrompt, isNot(contains('broken')));
      }
      expect(report.allCases.invalidCount, 0);
      expect(report.results.every((result) => result.matchesExpected), isTrue);
    },
  );

  test('counts false refutes and broken-work misses separately', () async {
    final report = await runLl37VerifierFidelityProbe(
      options: Ll37VerifierFidelityProbeOptions(
        showHelp: false,
        fixtureResponse: false,
        casePaths: [correctPath, brokenPath],
        timeoutSeconds: 1,
        baseUrl: 'http://unused.invalid/v1',
        model: 'fixture-model',
      ),
      complete: (prompt) async => jsonEncode({
        'verdict': prompt.caseId.endsWith('correct')
            ? 'refuted'
            : 'not_refuted',
        'confidence': 0.8,
        'findings': [
          {
            'kind': 'fixture',
            'location': 'lib/slugify_label.dart:1',
            'detail': 'Deliberate mismatch for metric coverage.',
          },
        ],
      }),
    );

    expect(report.allCases.falseRefuteCount, 1);
    expect(report.allCases.falseRefuteRate, 1);
    expect(report.allCases.brokenMissedCount, 1);
    expect(report.allCases.brokenRecall, 0);
  });

  test('keeps malformed and unverifiable model outputs visible', () async {
    final report = await runLl37VerifierFidelityProbe(
      options: Ll37VerifierFidelityProbeOptions(
        showHelp: false,
        fixtureResponse: false,
        casePaths: [correctPath, brokenPath],
        timeoutSeconds: 1,
        baseUrl: 'http://unused.invalid/v1',
        model: 'fixture-model',
      ),
      complete: (prompt) async {
        if (prompt.caseId.endsWith('correct')) return 'not JSON';
        return '```json\n'
            '{"verdict":"unverifiable","confidence":0.4,"findings":[]}'
            '\n```';
      },
    );

    expect(report.allCases.invalidCount, 1);
    expect(report.allCases.unverifiableCount, 1);
    expect(report.results.first.error, isNotNull);
    expect(report.results.last.verdict, Ll37VerifierVerdict.unverifiable);
  });

  test('rejects out-of-range confidence as invalid output', () async {
    final report = await runLl37VerifierFidelityProbe(
      options: Ll37VerifierFidelityProbeOptions(
        showHelp: false,
        fixtureResponse: false,
        casePaths: [correctPath, brokenPath],
        timeoutSeconds: 1,
        baseUrl: 'http://unused.invalid/v1',
        model: 'fixture-model',
      ),
      complete: (_) async => jsonEncode({
        'verdict': 'not_refuted',
        'confidence': 1.1,
        'findings': <Map<String, String>>[],
      }),
    );

    expect(report.allCases.invalidCount, 2);
    expect(
      report.results.every(
        (result) =>
            result.error == 'Verifier confidence must be between 0 and 1.',
      ),
      isTrue,
    );
  });

  test('requires complete paired correct and broken cases', () async {
    final correct = await Ll37VerifierFidelityCase.load(File(correctPath));

    expect(
      () => validateLl37VerifierFidelityPairs([correct]),
      throwsFormatException,
    );
    expect(
      () => validateLl37VerifierFidelityPairs([correct, correct]),
      throwsFormatException,
    );
  });

  test('rejects an attended source surface and missing consent', () async {
    final directory = await Directory.systemTemp.createTemp(
      'caverno_ll37_probe_invalid_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final fixtureCase =
        jsonDecode(await File(correctPath).readAsString())
            as Map<String, dynamic>;
    final fixtureManifest =
        jsonDecode(
              await File(
                _fixturePath('slugify_correct_manifest.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    fixtureCase['personalEvalManifestPath'] = 'manifest.json';
    fixtureCase['sourceSurface'] = 'chat';
    final caseFile = File('${directory.path}/case.json');
    final manifestFile = File('${directory.path}/manifest.json');
    await caseFile.writeAsString(jsonEncode(fixtureCase));
    await manifestFile.writeAsString(jsonEncode(fixtureManifest));

    await expectLater(
      Ll37VerifierFidelityCase.load(caseFile),
      throwsFormatException,
    );

    fixtureCase['sourceSurface'] = 'routine';
    final consent = fixtureManifest['consent'] as Map<String, dynamic>;
    consent['explicitUserConsent'] = false;
    await caseFile.writeAsString(jsonEncode(fixtureCase));
    await manifestFile.writeAsString(jsonEncode(fixtureManifest));

    await expectLater(
      Ll37VerifierFidelityCase.load(caseFile),
      throwsFormatException,
    );

    fixtureManifest['schemaVersion'] = 99;
    consent['explicitUserConsent'] = true;
    await manifestFile.writeAsString(jsonEncode(fixtureManifest));

    await expectLater(
      Ll37VerifierFidelityCase.load(caseFile),
      throwsFormatException,
    );
  });

  test('conservative gate requires enough clean cases on two surfaces', () {
    final results = <Ll37VerifierCaseResult>[];
    for (var index = 0; index < 5; index += 1) {
      results.add(
        _result(
          caseId: 'correct-$index',
          expected: Ll37ExpectedVerdict.notRefuted,
          verdict: Ll37VerifierVerdict.notRefuted,
          surface: index.isEven
              ? Ll37SourceSurface.routine
              : Ll37SourceSurface.worktreeAgent,
        ),
      );
      results.add(
        _result(
          caseId: 'broken-$index',
          expected: Ll37ExpectedVerdict.refuted,
          verdict: Ll37VerifierVerdict.refuted,
          surface: index.isEven
              ? Ll37SourceSurface.routine
              : Ll37SourceSurface.worktreeAgent,
        ),
      );
    }

    final ready = Ll37VerifierFidelityReport.build(
      generatedAt: DateTime.utc(2026, 8, 10),
      mode: 'fixture',
      model: 'model',
      baseUrl: 'local',
      results: results,
    );
    expect(ready.gate, 'go');

    final falseRefute = _result(
      caseId: 'correct-0',
      expected: Ll37ExpectedVerdict.notRefuted,
      verdict: Ll37VerifierVerdict.refuted,
      surface: Ll37SourceSurface.routine,
    );
    final blocked = Ll37VerifierFidelityReport.build(
      generatedAt: DateTime.utc(2026, 8, 10),
      mode: 'fixture',
      model: 'model',
      baseUrl: 'local',
      results: [falseRefute, ...results.skip(1)],
    );
    expect(blocked.gate, 'no_go_false_refute_rate');
  });

  test('parses CLI options and rejects unknown flags', () {
    final options = Ll37VerifierFidelityProbeOptions.parse([
      '--fixture-response',
      '--case',
      correctPath,
      '--case',
      brokenPath,
      '--out-json',
      'report.json',
      '--timeout-seconds',
      '3',
    ]);

    expect(options.fixtureResponse, isTrue);
    expect(options.casePaths, hasLength(2));
    expect(options.outJsonPath, 'report.json');
    expect(options.timeoutSeconds, 3);
    expect(
      () => Ll37VerifierFidelityProbeOptions.parse(const ['--wat']),
      throwsFormatException,
    );
  });

  test('sends a content-length body to OpenAI-compatible endpoints', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestFuture = server.first.then((request) async {
      final contentLength = request.headers.contentLength;
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"verdict":"not_refuted"}'},
            },
          ],
        }),
      );
      await request.response.close();
      return (contentLength: contentLength, body: body);
    });
    final client = OpenAiCompatibleLl37VerifierClient(
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      apiKey: 'no-key',
      model: 'fixture-model',
      timeout: const Duration(seconds: 2),
    );

    final completion = await client.complete(
      const Ll37VerifierPrompt(
        caseId: 'case-id',
        systemPrompt: 'System prompt',
        userPrompt: 'User prompt',
      ),
    );
    final captured = await requestFuture;

    expect(captured.contentLength, greaterThan(0));
    expect(captured.body['model'], 'fixture-model');
    expect(completion, '{"verdict":"not_refuted"}');
  });
}

Ll37VerifierCaseResult _result({
  required String caseId,
  required Ll37ExpectedVerdict expected,
  required Ll37VerifierVerdict verdict,
  required Ll37SourceSurface surface,
}) {
  final evalCase = Ll37VerifierFidelityCase(
    caseId: caseId,
    pairId: caseId.split('-').last,
    title: caseId,
    sourceSurface: surface,
    expectedVerdict: expected,
    objective: 'Objective',
    acceptanceCriteria: const ['Criterion'],
    changedFiles: const [
      {'path': 'lib/file.dart', 'content': 'content'},
    ],
    verificationEvidence: const [
      {'command': 'dart test', 'exitCode': 0},
    ],
    casePath: 'case.json',
    personalEvalManifestPath: 'manifest.json',
  );
  return Ll37VerifierCaseResult(
    evalCase: evalCase,
    rawResponse: '',
    verdict: verdict,
    confidence: 1,
    findings: const [],
  );
}

String _fixturePath(String name) {
  return '${Directory.current.path}/tool/fixtures/'
      'll37_verifier_fidelity/$name';
}
