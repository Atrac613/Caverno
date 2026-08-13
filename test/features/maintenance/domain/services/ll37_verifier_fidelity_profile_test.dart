import 'package:caverno/features/maintenance/domain/services/ll37_verifier_fidelity_profile.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const registry = Ll37VerifierFidelityRegistry();

  test('matches the accepted measured route with URL normalization', () {
    final profile = registry.eligibleProfile(
      provider: LlmProvider.openAiCompatible,
      baseUrl: ' HTTP://192.168.100.241:1234/v1/// ',
      model: 'qwen3.6-35b-a3b-vision',
    );

    expect(profile, isNotNull);
    expect(profile?.reportSchemaVersion, 3);
    expect(
      profile?.reportSha256,
      'c07819b6698dacc2f916f96eab2fdaa29230a63713cb7d7d80a5e12eefb86d3e',
    );
    expect(profile?.correctCaseCount, 5);
    expect(profile?.brokenCaseCount, 5);
    expect(profile?.meetsProductionThreshold, isTrue);
  });

  test('returns accepted routes in append-only order for one endpoint', () {
    final profiles = registry.eligibleProfiles(
      provider: LlmProvider.openAiCompatible,
      baseUrl: 'HTTP://192.168.100.241:1234/v1/',
    );

    expect(profiles.map((profile) => profile.model), [
      'qwen3.6-35b-a3b-vision',
      'qwen3.6-27b-vision',
    ]);
    expect(
      profiles.last.reportSha256,
      'ddca603486332ddb0502c634c224cad06611be976650d31ad12c2bdeee587d16',
    );
  });

  test('fails closed when provider or endpoint changes', () {
    expect(
      registry.eligibleProfile(
        provider: LlmProvider.appleFoundationModels,
        baseUrl: 'http://192.168.100.241:1234/v1',
        model: 'qwen3.6-35b-a3b-vision',
      ),
      isNull,
    );
    expect(
      registry.eligibleProfile(
        provider: LlmProvider.openAiCompatible,
        baseUrl: 'http://192.168.100.242:1234/v1',
        model: 'qwen3.6-35b-a3b-vision',
      ),
      isNull,
    );
    expect(
      registry.eligibleProfiles(
        provider: LlmProvider.openAiCompatible,
        baseUrl: 'http://192.168.100.242:1234/v1',
      ),
      isEmpty,
    );
    expect(
      registry.eligibleProfile(
        provider: LlmProvider.openAiCompatible,
        baseUrl: 'http://192.168.100.241:1234/v1',
        model: 'unmeasured-model',
      ),
      isNull,
    );
  });

  test('rejects a route record whose evidence misses a threshold', () {
    const profile = Ll37VerifierFidelityProfile(
      provider: LlmProvider.openAiCompatible,
      baseUrl: 'http://localhost:1234/v1',
      model: 'candidate',
      gate: Ll37VerifierFidelityGate.go,
      reportSchemaVersion: 3,
      reportSha256: 'evidence-hash',
      measuredAt: '2026-08-13T00:00:00Z',
      correctCaseCount: 5,
      brokenCaseCount: 5,
      distinctObjectiveCount: 4,
      sourceSurfaceCount: 2,
      falseRefuteRate: 0,
      brokenRecall: 1,
      invalidOrUnverifiableCount: 0,
    );
    const insufficient = Ll37VerifierFidelityRegistry(profiles: [profile]);

    expect(profile.meetsProductionThreshold, isFalse);
    expect(
      insufficient.eligibleProfile(
        provider: LlmProvider.openAiCompatible,
        baseUrl: 'http://localhost:1234/v1',
        model: 'candidate',
      ),
      isNull,
    );
  });
}
