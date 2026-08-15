import '../entities/app_settings.dart';
import 'model_capability_physical_metrics.dart';

enum ModelCapabilityComparisonDirection { higherIsBetter, lowerIsBetter }

class ModelCapabilityComparisonAxis {
  const ModelCapabilityComparisonAxis({
    required this.id,
    required this.metadataKey,
    required this.labelKey,
    required this.unit,
    required this.direction,
    this.decimalPlaces = 0,
  });

  final String id;
  final String metadataKey;
  final String labelKey;
  final String unit;
  final ModelCapabilityComparisonDirection direction;
  final int decimalPlaces;
}

class ModelCapabilityComparisonSample {
  const ModelCapabilityComparisonSample({
    required this.profileId,
    required this.model,
    required this.value,
  });

  final String profileId;
  final String model;
  final double value;
}

class ModelCapabilityComparisonResult {
  const ModelCapabilityComparisonResult({
    required this.axis,
    required this.samples,
    required this.bestProfileIds,
  });

  final ModelCapabilityComparisonAxis axis;
  final List<ModelCapabilityComparisonSample> samples;
  final Set<String> bestProfileIds;

  bool get isComparable => samples.length >= 2;

  String formatValue(double value) {
    final formatted = axis.decimalPlaces == 0
        ? value.round().toString()
        : value.toStringAsFixed(axis.decimalPlaces);
    return '$formatted ${axis.unit}';
  }
}

/// Per-axis ordering for LL39 physical capability evidence.
///
/// There is intentionally no overall ordering here. TTFT, decode throughput,
/// context capacity, turns, and token cost answer different questions; merging
/// them would recreate the arbitrary weighted denominator LL39 removed.
class ModelCapabilityComparison {
  const ModelCapabilityComparison._();

  static const axes = <ModelCapabilityComparisonAxis>[
    ModelCapabilityComparisonAxis(
      id: 'effective-context',
      metadataKey: ModelCapabilityPhysicalMetrics.effectiveContextPromptTokens,
      labelKey: 'settings.live_llm_diag_context_measured',
      unit: 'tok',
      direction: ModelCapabilityComparisonDirection.higherIsBetter,
    ),
    ModelCapabilityComparisonAxis(
      id: 'decode-rate',
      metadataKey:
          ModelCapabilityPhysicalMetrics.streamingDecodeTokensPerSecond,
      labelKey: 'settings.live_llm_diag_decode_rate',
      unit: 'tok/s',
      direction: ModelCapabilityComparisonDirection.higherIsBetter,
      decimalPlaces: 2,
    ),
    ModelCapabilityComparisonAxis(
      id: 'ttft',
      metadataKey: ModelCapabilityPhysicalMetrics.streamingTtftMs,
      labelKey: 'settings.live_llm_diag_ttft',
      unit: 'ms',
      direction: ModelCapabilityComparisonDirection.lowerIsBetter,
    ),
    ModelCapabilityComparisonAxis(
      id: 'tool-loop-turns',
      metadataKey: ModelCapabilityPhysicalMetrics.toolLoopModelTurns,
      labelKey: 'settings.live_llm_diag_loop_turns',
      unit: 'turns',
      direction: ModelCapabilityComparisonDirection.lowerIsBetter,
    ),
    ModelCapabilityComparisonAxis(
      id: 'tool-loop-tokens',
      metadataKey: ModelCapabilityPhysicalMetrics.toolLoopTotalTokens,
      labelKey: 'settings.live_llm_diag_loop_total_tokens',
      unit: 'tok',
      direction: ModelCapabilityComparisonDirection.lowerIsBetter,
    ),
  ];

  static List<ModelCapabilityComparisonResult> evaluate(
    Iterable<ModelCapabilityProfile> profiles,
  ) {
    final unique = <String, ModelCapabilityProfile>{};
    for (final profile in profiles) {
      final normalized = profile.normalizedForPersistence();
      if (normalized.normalizedModel.isNotEmpty) {
        unique[normalized.computedId] = normalized;
      }
    }

    // An axis nobody measured is dropped rather than rendered empty: a card
    // with no models under it reads as a failed comparison, not as an
    // unrequested measurement.
    return List.unmodifiable([
      for (final axis in axes)
        if (_evaluateAxis(axis, unique.values) case final result
            when result.samples.isNotEmpty)
          result,
    ]);
  }

  static ModelCapabilityComparisonResult _evaluateAxis(
    ModelCapabilityComparisonAxis axis,
    Iterable<ModelCapabilityProfile> profiles,
  ) {
    final samples = <ModelCapabilityComparisonSample>[];
    for (final profile in profiles) {
      final value = _metricValue(profile, axis);
      if (value == null) continue;
      samples.add(
        ModelCapabilityComparisonSample(
          profileId: profile.computedId,
          model: profile.normalizedModel,
          value: value,
        ),
      );
    }
    samples.sort((a, b) {
      final valueOrder =
          axis.direction == ModelCapabilityComparisonDirection.higherIsBetter
          ? b.value.compareTo(a.value)
          : a.value.compareTo(b.value);
      if (valueOrder != 0) return valueOrder;
      return a.profileId.compareTo(b.profileId);
    });
    final bestValue = samples.isEmpty ? null : samples.first.value;
    return ModelCapabilityComparisonResult(
      axis: axis,
      samples: List.unmodifiable(samples),
      bestProfileIds: Set.unmodifiable({
        for (final sample in samples)
          if (sample.value == bestValue) sample.profileId,
      }),
    );
  }

  static double? _metricValue(
    ModelCapabilityProfile profile,
    ModelCapabilityComparisonAxis axis,
  ) {
    var raw = profile.probeMetadata[axis.metadataKey];
    if (raw == null && axis.id == 'effective-context') {
      if (profile.probeMetadata['difficultyLadderAxis'] ==
          'effective_context_recall') {
        raw = profile.probeMetadata['difficultyLadderMeasuredPromptTokens'];
      }
    }
    final value = double.tryParse(raw?.trim() ?? '');
    // Zero is not a measurement on any of these axes -- no model answers in
    // 0 ms, decodes 0 tokens per second, or recalls 0 tokens of context. It is
    // what a skipped probe writes, and reading it as a value ranked three
    // models at "0 tok" and handed every one of them the best-in-axis marker.
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }
}
