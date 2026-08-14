import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/model_benchmark_saturation_watchdog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const suite = 'cavernobench-v9';

  test('one high-water model is not enough to declare saturation', () {
    final watchdog = ModelBenchmarkSaturationWatchdog.evaluate(
      profiles: [_profile('model-a', points: 1000)],
      suite: suite,
    );

    expect(watchdog.registeredModelCount, 1);
    expect(watchdog.highWaterModelCount, 1);
    expect(watchdog.isSaturated, isFalse);
  });

  test('all registered current-suite models at 95 percent saturate', () {
    final watchdog = ModelBenchmarkSaturationWatchdog.evaluate(
      profiles: [
        _profile('model-a', points: 950),
        _profile('model-b', points: 1000),
      ],
      suite: suite,
    );

    expect(watchdog.hasCompleteCoverage, isTrue);
    expect(watchdog.denominatorConsistent, isTrue);
    expect(watchdog.highWaterModelCount, 2);
    expect(watchdog.isSaturated, isTrue);
    expect(watchdog.toJson()['isSaturated'], isTrue);
  });

  test('one model below the high-water threshold keeps discrimination', () {
    final watchdog = ModelBenchmarkSaturationWatchdog.evaluate(
      profiles: [
        _profile('model-a', points: 949),
        _profile('model-b', points: 1000),
      ],
      suite: suite,
    );

    expect(watchdog.highWaterModelCount, 1);
    expect(watchdog.isSaturated, isFalse);
  });

  test('missing or stale score evidence fails closed', () {
    final watchdog = ModelBenchmarkSaturationWatchdog.evaluate(
      profiles: [
        _profile('model-a', points: 1000),
        _profile('model-b', points: null),
        _profile('model-c', points: 1000, suite: 'cavernobench-v7'),
      ],
      suite: suite,
    );

    expect(watchdog.registeredModelCount, 3);
    expect(watchdog.scoredModelCount, 1);
    expect(watchdog.hasCompleteCoverage, isFalse);
    expect(watchdog.isSaturated, isFalse);
  });

  test('different denominators cannot declare suite saturation', () {
    final watchdog = ModelBenchmarkSaturationWatchdog.evaluate(
      profiles: [
        _profile('model-a', points: 950),
        _profile('model-b', points: 1900, maximum: 2000),
      ],
      suite: suite,
    );

    expect(watchdog.hasCompleteCoverage, isTrue);
    expect(watchdog.denominatorConsistent, isFalse);
    expect(watchdog.isSaturated, isFalse);
  });

  test('out-of-range points are rejected instead of clamped to high water', () {
    final watchdog = ModelBenchmarkSaturationWatchdog.evaluate(
      profiles: [
        _profile('model-a', points: 1001),
        _profile('model-b', points: 1000),
      ],
      suite: suite,
    );

    expect(watchdog.scoredModelCount, 1);
    expect(watchdog.hasCompleteCoverage, isFalse);
    expect(watchdog.isSaturated, isFalse);
  });

  test('duplicate profile ids use the latest registered value', () {
    final watchdog = ModelBenchmarkSaturationWatchdog.evaluate(
      profiles: [
        _profile('model-a', points: 400),
        _profile('model-a', points: 1000),
        _profile('model-b', points: 950),
      ],
      suite: suite,
    );

    expect(watchdog.registeredModelCount, 2);
    expect(watchdog.scoredModelCount, 2);
    expect(watchdog.isSaturated, isTrue);
  });
}

ModelCapabilityProfile _profile(
  String model, {
  required int? points,
  int maximum = 1000,
  String suite = 'cavernobench-v9',
}) {
  return ModelCapabilityProfile(
    id: 'stale-$model',
    baseUrl: 'http://localhost:1234/v1',
    model: model,
    probeMetadata: points == null
        ? const {}
        : {
            'benchmarkSuite': suite,
            'benchmarkPoints': '$points',
            'benchmarkMaxPoints': '$maximum',
          },
  );
}
