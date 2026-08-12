import 'dart:convert';

import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PersonalEvalCase readyCase() => PersonalEvalCase(
    caseId: 'case-1',
    title: 'Fix the login crash',
    prompt: '  Fix the login crash  ',
    repoStateRef: '  abc123  ',
    verificationCommand: '  flutter test  ',
    verificationResult: PersonalEvalVerificationResult.passed,
    workspaceMode: 'coding',
    split: PersonalEvalCaseSplit.heldOut,
    consentGranted: true,
    consentedAt: DateTime.utc(2026, 6, 15, 1, 2, 3),
    createdAt: DateTime.utc(2026, 6, 15, 1, 2, 3),
  );

  test('defaults are safe and local-only', () {
    const minimal = PersonalEvalCase(
      caseId: 'c',
      prompt: 'p',
      repoStateRef: 'r',
    );

    expect(minimal.split, PersonalEvalCaseSplit.heldIn);
    expect(
      minimal.verificationResult,
      PersonalEvalVerificationResult.inconclusive,
    );
    expect(minimal.consentGranted, isFalse);
    expect(minimal.excludedFromExport, isTrue);
  });

  test('readiness reflects consent, required fields, and verification', () {
    const noConsent = PersonalEvalCase(
      caseId: 'c',
      prompt: 'p',
      repoStateRef: 'r',
    );
    expect(noConsent.readiness, PersonalEvalCaseReadiness.blocked);

    const missingRepo = PersonalEvalCase(
      caseId: 'c',
      prompt: 'p',
      repoStateRef: '   ',
      consentGranted: true,
    );
    expect(missingRepo.readiness, PersonalEvalCaseReadiness.blocked);

    const noVerification = PersonalEvalCase(
      caseId: 'c',
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
    );
    expect(
      noVerification.readiness,
      PersonalEvalCaseReadiness.reviewRecommended,
    );

    expect(readyCase().readiness, PersonalEvalCaseReadiness.ready);
  });

  test('builds a CLI-compatible case manifest artifact', () {
    final json = readyCase().toCaseManifestJson();

    expect(json['schemaName'], 'caverno_personal_eval_case_manifest');
    expect(json['schemaVersion'], 1);
    expect(json['caseId'], 'case-1');
    expect(json['readiness'], 'ready');
    expect(json['split'], 'heldOut');

    final task = json['task'] as Map<String, dynamic>;
    // Task fields are trimmed and the verification result uses the enum name.
    expect(task['prompt'], 'Fix the login crash');
    expect(task['repoStateRef'], 'abc123');
    expect(task['verificationCommand'], 'flutter test');
    expect(task['verificationResult'], 'passed');
    expect(task['workspaceMode'], 'coding');

    final consent = json['consent'] as Map<String, dynamic>;
    expect(consent['explicitUserConsent'], isTrue);
    expect(consent['scope'], 'personal_eval_case_recording');

    final privacy = json['privacy'] as Map<String, dynamic>;
    expect(privacy['localOnly'], isTrue);
    expect(privacy['exportPolicy'], 'excluded_by_default');
  });

  test('omits an empty verification command from the manifest', () {
    const noVerification = PersonalEvalCase(
      caseId: 'c',
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
    );

    final task =
        noVerification.toCaseManifestJson()['task'] as Map<String, dynamic>;
    expect(task.containsKey('verificationCommand'), isFalse);
    expect(
      noVerification.toCaseManifestJson()['readiness'],
      'review_recommended',
    );
  });

  test('survives a JSON round-trip with unknown enum fallback', () {
    final decoded = PersonalEvalCase.fromJson(
      jsonDecode(jsonEncode(readyCase().toJson())) as Map<String, dynamic>,
    );
    expect(decoded.split, PersonalEvalCaseSplit.heldOut);
    expect(decoded.verificationResult, PersonalEvalVerificationResult.passed);

    final futureEnum =
        jsonDecode(jsonEncode(readyCase().toJson())) as Map<String, dynamic>
          ..['split'] = 'futureSplit'
          ..['verificationResult'] = 'futureResult';
    final fallback = PersonalEvalCase.fromJson(futureEnum);
    expect(fallback.split, PersonalEvalCaseSplit.heldIn);
    expect(
      fallback.verificationResult,
      PersonalEvalVerificationResult.inconclusive,
    );
  });

  group('authored fixture cases', () {
    PersonalEvalCase authoredCase({
      String fixtureDirectory = 'tool/personal_eval_corpus/fixtures/parser',
      String? verificationCommand = 'dart test test/parser_test.dart',
    }) => PersonalEvalCase(
      caseId: 'authored-1',
      title: 'Repair the parser',
      prompt: 'Make the failing parser test pass.',
      repoStateRef: '',
      fixtureDirectory: fixtureDirectory,
      verificationCommand: verificationCommand,
      origin: PersonalEvalCaseOrigin.authored,
      tier: 2,
      promptStyle: PersonalEvalPromptStyle.unguided,
      createdAt: DateTime.utc(2026, 8, 12),
    );

    test('is ready on reproducibility, not on consent', () {
      final authored = authoredCase();

      // No consent is recorded and no repo ref exists: an authored task has no
      // user data to consent to, and its state is the committed fixture.
      expect(authored.consentGranted, isFalse);
      expect(authored.normalizedRepoStateRef, isEmpty);
      expect(authored.readiness, PersonalEvalCaseReadiness.ready);
    });

    test('is blocked without a fixture directory', () {
      // A replay with nowhere to run would edit whatever tree it was handed.
      expect(
        authoredCase(fixtureDirectory: '   ').readiness,
        PersonalEvalCaseReadiness.blocked,
      );
    });

    test('is review-recommended without a verification command', () {
      expect(
        authoredCase(verificationCommand: null).readiness,
        PersonalEvalCaseReadiness.reviewRecommended,
      );
    });

    test('is shareable while recorded cases stay local-only', () {
      expect(authoredCase().excludedFromExport, isFalse);
      expect(readyCase().excludedFromExport, isTrue);
    });

    test('carries its origin and fixture into the manifest', () {
      final manifest = authoredCase().toCaseManifestJson();
      final task = manifest['task'] as Map<String, dynamic>;
      final privacy = manifest['privacy'] as Map<String, dynamic>;

      expect(manifest['origin'], 'authored');
      expect(manifest['tier'], 2);
      expect(manifest['promptStyle'], 'unguided');
      expect(
        task['fixtureDirectory'],
        'tool/personal_eval_corpus/fixtures/parser',
      );
      expect(privacy['localOnly'], isFalse);
      expect(privacy['exportPolicy'], 'shareable');
    });

    test('recorded cases keep their existing manifest shape', () {
      final manifest = readyCase().toCaseManifestJson();
      final privacy = manifest['privacy'] as Map<String, dynamic>;

      expect(manifest['origin'], 'recorded');
      expect(manifest.containsKey('tier'), isFalse);
      expect(manifest.containsKey('promptStyle'), isFalse);
      expect(
        (manifest['task'] as Map<String, dynamic>)['fixtureDirectory'],
        isNull,
      );
      expect(privacy['localOnly'], isTrue);
      expect(privacy['exportPolicy'], 'excluded_by_default');
      expect(
        (manifest['consent'] as Map<String, dynamic>)['scope'],
        'personal_eval_case_recording',
      );
    });

    test('an unknown future origin falls back to recorded', () {
      final json =
          jsonDecode(jsonEncode(authoredCase().toJson()))
                as Map<String, dynamic>
            ..['origin'] = 'futureOrigin';

      // Falling back to recorded is the safe direction: it keeps a case
      // local-only rather than treating unknown provenance as shareable.
      expect(
        PersonalEvalCase.fromJson(json).origin,
        PersonalEvalCaseOrigin.recorded,
      );
    });
  });
}
