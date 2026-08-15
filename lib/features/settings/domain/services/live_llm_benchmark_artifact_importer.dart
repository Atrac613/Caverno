import '../entities/app_settings.dart';
import 'model_capability_physical_metrics.dart';

/// Converts a headless LL39 benchmark artifact into revision-safe profile
/// evidence.
///
/// Focused capability runs intentionally attempt no conformance points. Their
/// physical evidence is useful, but recording `0/1000` would make the
/// saturation watchdog treat an unscored run as a failed model. The importer
/// therefore merges only evidence the artifact actually measured.
class LiveLlmBenchmarkArtifactImporter {
  const LiveLlmBenchmarkArtifactImporter._();

  static const schema = 'caverno_live_llm_benchmark_canary';

  static ModelCapabilityProfile importProfile(
    Map<String, dynamic> artifact, {
    Iterable<ModelCapabilityProfile> existingProfiles = const [],
  }) {
    if (_string(artifact['schema']) != schema) {
      throw const FormatException('Unsupported benchmark artifact schema');
    }

    final model = _requiredString(artifact, 'model');
    final baseUrl = _requiredString(artifact, 'baseUrl');
    final provider = _provider(artifact['provider'], baseUrl);
    final generatedAt = _requiredDateTime(artifact, 'generatedAt');
    final runs = _mapList(artifact['runs'], field: 'runs');
    if (runs.isEmpty) {
      throw const FormatException('Benchmark artifact contains no runs');
    }
    final run = runs.last;
    final probedAt = _optionalDateTime(run['finishedAt']) ?? generatedAt;
    final runModel = _string(run['model']);
    final runBaseUrl = _string(run['baseUrl']);
    if ((runModel.isNotEmpty && runModel != model) ||
        (runBaseUrl.isNotEmpty && runBaseUrl != baseUrl)) {
      throw const FormatException(
        'Benchmark artifact run identity does not match its header',
      );
    }

    ModelCapabilityProfile? existing;
    for (final candidate in existingProfiles) {
      if (candidate.matches(
        provider: provider,
        baseUrl: baseUrl,
        model: model,
      )) {
        existing = candidate.normalizedForPersistence();
      }
    }
    final previousTime = existing?.probedAt;
    if (previousTime != null && probedAt.isBefore(previousTime)) {
      throw const FormatException(
        'Benchmark artifact is older than the stored model profile',
      );
    }

    final importedMetadata = <String, String>{};
    final benchmark = _optionalMap(run['benchmark'], field: 'benchmark');
    final attemptedPoints = _optionalInt(benchmark?['attemptedPoints']);
    if (benchmark != null && attemptedPoints != null && attemptedPoints > 0) {
      final suiteId = _requiredString(benchmark, 'suiteId');
      final suiteVersion = _requiredPositiveInt(benchmark, 'suiteVersion');
      final artifactSuiteId = _requiredString(artifact, 'suiteId');
      final artifactSuiteVersion = _requiredPositiveInt(
        artifact,
        'suiteVersion',
      );
      if (suiteId != artifactSuiteId || suiteVersion != artifactSuiteVersion) {
        throw const FormatException(
          'Benchmark run suite does not match the artifact header',
        );
      }
      final points = _requiredNonNegativeInt(benchmark, 'earnedPoints');
      final maximum = _requiredPositiveInt(benchmark, 'maxPoints');
      if (points > maximum || attemptedPoints > maximum) {
        throw const FormatException(
          'Benchmark points exceed the fixed maximum',
        );
      }
      importedMetadata.addAll({
        'benchmarkSuite': '$suiteId-v$suiteVersion',
        'benchmarkPoints': '$points',
        'benchmarkAttemptedPoints': '$attemptedPoints',
        'benchmarkMaxPoints': '$maximum',
      });
    }

    var measuredContextTokens = 0;
    final ladder = _optionalMap(
      run['difficultyLadder'],
      field: 'difficultyLadder',
    );
    if (ladder != null && ladder['measured'] == true) {
      final suite = _requiredString(ladder, 'suite');
      final ladderId = _requiredString(ladder, 'suiteId');
      final ladderVersion = _requiredPositiveInt(ladder, 'suiteVersion');
      if (suite != '$ladderId-v$ladderVersion') {
        throw const FormatException('Difficulty ladder suite is inconsistent');
      }
      final axis = _requiredString(ladder, 'axis');
      final unit = _requiredString(ladder, 'unit');
      if (unit != 'prompt_tokens') {
        throw const FormatException('Unsupported difficulty ladder unit');
      }
      measuredContextTokens = _requiredPositiveInt(
        ladder,
        'measuredPromptTokens',
      );
      final highest = _requiredNonNegativeInt(
        ladder,
        'highestPassedStagePromptTokens',
      );
      final passedCount = _requiredNonNegativeInt(ladder, 'passedStageCount');
      final stageCount = _requiredPositiveInt(ladder, 'stageCount');
      final next = _optionalInt(ladder['nextStagePromptTokens']);
      if (highest > measuredContextTokens ||
          passedCount > stageCount ||
          (next != null && next <= measuredContextTokens)) {
        throw const FormatException('Invalid difficulty ladder stage evidence');
      }
      importedMetadata.addAll({
        'difficultyLadder': suite,
        'difficultyLadderAxis': axis,
        'difficultyLadderUnit': unit,
        // An unclimbed ladder carries no measurement; see the profile builder.
        if (measuredContextTokens > 0)
          'difficultyLadderMeasuredPromptTokens': '$measuredContextTokens',
        if (measuredContextTokens > 0)
          'difficultyLadderHighestStagePromptTokens': '$highest',
        if (next != null) 'difficultyLadderNextStagePromptTokens': '$next',
        'difficultyLadderPassedStageCount': '$passedCount',
        'difficultyLadderStageCount': '$stageCount',
      });
    }
    importedMetadata.addAll(
      ModelCapabilityPhysicalMetrics.fromBenchmarkRun(run),
    );

    if (importedMetadata.isEmpty) {
      throw const FormatException(
        'Benchmark artifact contains no measured score or ladder evidence',
      );
    }

    final base =
        existing ??
        ModelCapabilityProfile(
          id: '',
          provider: provider,
          baseUrl: baseUrl,
          model: model,
        );
    final profile = base.copyWith(
      provider: provider,
      baseUrl: baseUrl,
      model: model,
      usableContextTokens: measuredContextTokens > 0
          ? measuredContextTokens
          : base.usableContextTokens,
      probedAt: probedAt,
      probeSummary: _summary(importedMetadata),
      probeMetadata: {...base.probeMetadata, ...importedMetadata},
    );
    return profile.normalizedForPersistence();
  }

  static String _summary(Map<String, String> metadata) {
    final parts = <String>[];
    final points = metadata['benchmarkPoints'];
    final maximum = metadata['benchmarkMaxPoints'];
    if (points != null && maximum != null) {
      parts.add('benchmark $points/$maximum');
    }
    final measured = metadata['difficultyLadderMeasuredPromptTokens'];
    if (measured != null) {
      parts.add('effective context $measured prompt tokens');
    }
    return 'Imported LL39 artifact: ${parts.join(', ')}.';
  }

  static LlmProvider _provider(Object? value, String baseUrl) {
    final name = _string(value);
    if (name.isEmpty) {
      return baseUrl == 'apple-foundation-models://local'
          ? LlmProvider.appleFoundationModels
          : LlmProvider.openAiCompatible;
    }
    return LlmProvider.values.firstWhere(
      (provider) => provider.name == name,
      orElse: () => throw const FormatException(
        'Unsupported benchmark artifact provider',
      ),
    );
  }

  static List<Map<String, dynamic>> _mapList(
    Object? value, {
    required String field,
  }) {
    if (value is! List) {
      throw FormatException('$field must be a JSON array');
    }
    return [
      for (final item in value)
        if (item is Map<String, dynamic>)
          item
        else
          throw FormatException('$field must contain JSON objects'),
    ];
  }

  static Map<String, dynamic>? _optionalMap(
    Object? value, {
    required String field,
  }) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    throw FormatException('$field must be a JSON object');
  }

  static String _requiredString(Map<String, dynamic> json, String field) {
    final value = _string(json[field]);
    if (value.isEmpty) throw FormatException('$field must not be empty');
    return value;
  }

  static int _requiredPositiveInt(Map<String, dynamic> json, String field) {
    final value = _optionalInt(json[field]);
    if (value == null || value <= 0) {
      throw FormatException('$field must be a positive integer');
    }
    return value;
  }

  static int _requiredNonNegativeInt(Map<String, dynamic> json, String field) {
    final value = _optionalInt(json[field]);
    if (value == null || value < 0) {
      throw FormatException('$field must be a non-negative integer');
    }
    return value;
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String field) {
    final value = _optionalDateTime(json[field]);
    if (value == null) throw FormatException('$field must be an ISO timestamp');
    return value;
  }

  static DateTime? _optionalDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static int? _optionalInt(Object? value) => switch (value) {
    int number => number,
    num number when number.isFinite && number == number.roundToDouble() =>
      number.toInt(),
    _ => null,
  };

  static String _string(Object? value) => value is String ? value.trim() : '';
}
