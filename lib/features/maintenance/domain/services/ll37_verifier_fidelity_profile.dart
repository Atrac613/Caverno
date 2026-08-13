import '../../../settings/domain/entities/app_settings.dart';

enum Ll37VerifierFidelityGate { go, noGo }

/// An auditable verifier route whose objective-verdict fidelity was measured.
class Ll37VerifierFidelityProfile {
  const Ll37VerifierFidelityProfile({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.gate,
    required this.reportSchemaVersion,
    required this.reportSha256,
    required this.measuredAt,
    required this.correctCaseCount,
    required this.brokenCaseCount,
    required this.distinctObjectiveCount,
    required this.sourceSurfaceCount,
    required this.falseRefuteRate,
    required this.brokenRecall,
    required this.invalidOrUnverifiableCount,
  });

  final LlmProvider provider;
  final String baseUrl;
  final String model;
  final Ll37VerifierFidelityGate gate;
  final int reportSchemaVersion;
  final String reportSha256;
  final String measuredAt;
  final int correctCaseCount;
  final int brokenCaseCount;
  final int distinctObjectiveCount;
  final int sourceSurfaceCount;
  final double falseRefuteRate;
  final double brokenRecall;
  final int invalidOrUnverifiableCount;

  bool get meetsProductionThreshold {
    return gate == Ll37VerifierFidelityGate.go &&
        reportSchemaVersion == 3 &&
        reportSha256.trim().isNotEmpty &&
        correctCaseCount >= 5 &&
        brokenCaseCount >= 5 &&
        distinctObjectiveCount >= 5 &&
        sourceSurfaceCount >= 2 &&
        falseRefuteRate <= 0.1 &&
        brokenRecall >= 0.8 &&
        invalidOrUnverifiableCount == 0;
  }

  String get profileKey =>
      buildProfileKey(provider: provider, baseUrl: baseUrl, model: model);

  bool matches({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    return meetsProductionThreshold &&
        profileKey ==
            buildProfileKey(provider: provider, baseUrl: baseUrl, model: model);
  }

  bool matchesEndpoint({
    required LlmProvider provider,
    required String baseUrl,
  }) {
    return meetsProductionThreshold &&
        this.provider == provider &&
        _normalizeBaseUrl(this.baseUrl) == _normalizeBaseUrl(baseUrl);
  }

  static String buildProfileKey({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    return '${provider.name}|$normalizedUrl|${model.trim()}';
  }

  static String _normalizeBaseUrl(String baseUrl) =>
      baseUrl.trim().replaceFirst(RegExp(r'/+$'), '').toLowerCase();
}

class Ll37VerifierFidelityRegistry {
  const Ll37VerifierFidelityRegistry({this.profiles = acceptedProfiles});

  static const List<Ll37VerifierFidelityProfile> acceptedProfiles = [
    Ll37VerifierFidelityProfile(
      provider: LlmProvider.openAiCompatible,
      baseUrl: 'http://192.168.100.241:1234/v1',
      model: 'qwen3.6-35b-a3b-vision',
      gate: Ll37VerifierFidelityGate.go,
      reportSchemaVersion: 3,
      reportSha256:
          'c07819b6698dacc2f916f96eab2fdaa29230a63713cb7d7d80a5e12eefb86d3e',
      measuredAt: '2026-08-13T01:06:30.831690Z',
      correctCaseCount: 5,
      brokenCaseCount: 5,
      distinctObjectiveCount: 5,
      sourceSurfaceCount: 2,
      falseRefuteRate: 0,
      brokenRecall: 1,
      invalidOrUnverifiableCount: 0,
    ),
    Ll37VerifierFidelityProfile(
      provider: LlmProvider.openAiCompatible,
      baseUrl: 'http://192.168.100.241:1234/v1',
      model: 'qwen3.6-27b-vision',
      gate: Ll37VerifierFidelityGate.go,
      reportSchemaVersion: 3,
      reportSha256:
          'ddca603486332ddb0502c634c224cad06611be976650d31ad12c2bdeee587d16',
      measuredAt: '2026-08-13T03:12:05.136826Z',
      correctCaseCount: 5,
      brokenCaseCount: 5,
      distinctObjectiveCount: 5,
      sourceSurfaceCount: 2,
      falseRefuteRate: 0,
      brokenRecall: 1,
      invalidOrUnverifiableCount: 0,
    ),
  ];

  final List<Ll37VerifierFidelityProfile> profiles;

  Ll37VerifierFidelityProfile? eligibleProfile({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    for (final profile in profiles) {
      if (profile.matches(provider: provider, baseUrl: baseUrl, model: model)) {
        return profile;
      }
    }
    return null;
  }

  List<Ll37VerifierFidelityProfile> eligibleProfiles({
    required LlmProvider provider,
    required String baseUrl,
  }) {
    return profiles
        .where(
          (profile) =>
              profile.matchesEndpoint(provider: provider, baseUrl: baseUrl),
        )
        .toList(growable: false);
  }
}
