import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ana0_assumption_marking_measurement.dart';

/// Anabasis ANA0 PR 3c — the instrument, before the number it produces.
///
/// A measurement gets believed. This repository has already paid for one that
/// counted its own shadow, and for a probe that scored a capable model 0/30 on
/// its own wording, so the scoring runs here against scripted responses whose
/// correct verdict is known before the model is ever asked.

const _scenario = AssumptionScenario(
  id: 'incremental-sync',
  request: 'Add iCloud sync so records converge within one cycle. Plan it.',
  groundingMessage:
      'The backend already exposes GET /v1/notes/changes?since=<cursor>.',
  assumedFact: 'the backend supports incremental sync',
);

String _proposal(
  List<String> constraints, {
  List<String> openQuestions = const [],
}) => jsonEncode({
  'kind': 'proposal',
  'workflowStage': 'plan',
  'goal': 'Add iCloud synchronization',
  'constraints': constraints,
  'acceptanceCriteria': ['Records converge within one sync cycle'],
  'openQuestions': openQuestions,
  'decisions': <Map<String, dynamic>>[],
});

const _question = 'Does the backend support incremental sync?';

const _marked = 'The backend exposes incremental sync (assumed, material)';
const _softMarked = 'The backend exposes incremental sync (assumed)';
const _unmarked = 'The backend exposes incremental sync';

ArmObservation _score(String raw, {required ScenarioArm arm}) => scoreResponse(
  scenarioId: _scenario.id,
  arm: arm,
  repeat: 1,
  rawContent: raw,
);

MeasurementSummary _summary(List<ArmObservation> observations) =>
    MeasurementSummary(
      model: 'scripted',
      endpoint: 'scripted',
      compact: false,
      observations: observations,
    );

void main() {
  group('scoring one response', () {
    test('a material marker is counted as a material assumption', () {
      final observation = _score(
        _proposal([_marked]),
        arm: ScenarioArm.ungrounded,
      );

      expect(observation.parsed, isTrue);
      expect(observation.assumedCount, 1);
      expect(observation.materialCount, 1);
    });

    test('a bare "(assumed)" is an assumption but not a material one', () {
      final observation = _score(
        _proposal([_softMarked]),
        arm: ScenarioArm.ungrounded,
      );

      expect(observation.assumedCount, 1);
      expect(
        observation.materialCount,
        0,
        reason:
            'Materiality is what decides whether PR 4 would block, so the two '
            'must not be collapsed into one count.',
      );
    });

    test('an unmarked plan scores zero without being unparsed', () {
      final observation = _score(
        _proposal([_unmarked]),
        arm: ScenarioArm.ungrounded,
      );

      expect(observation.parsed, isTrue);
      expect(observation.materialCount, 0);
      expect(observation.itemCount, greaterThan(0));
    });

    test('a response that is not a proposal is unscored, not unmarked', () {
      final observation = _score(
        'I would start by checking whether the backend supports sync.',
        arm: ScenarioArm.ungrounded,
      );

      expect(observation.parsed, isFalse);
      expect(
        observation.failure,
        isNotNull,
        reason:
            'Counting prose as an unmarked plan would inflate the '
            'over-assertion rate with responses that asserted nothing.',
      );
    });

    test('a marker the model put on a question is counted, then dropped', () {
      // Both halves matter. PR 3d stops the mark from blocking anything, so it
      // never reaches provenance -- and if the instrument read only provenance
      // the behaviour would vanish from the measurement at the same moment it
      // was fixed, which is how a summary starts agreeing with its own patch.
      final observation = _score(
        _proposal(
          [_unmarked],
          openQuestions: ['$_question (assumed, material)'],
        ),
        arm: ScenarioArm.ungrounded,
      );

      expect(observation.markedOpenQuestionCount, 1);
      expect(
        observation.materialCount,
        0,
        reason: 'A marked question must not read as a blocking assumption.',
      );
      expect(observation.openQuestionCount, 1);
    });

    test('a fenced JSON block is read the way production reads it', () {
      final observation = _score(
        '```json\n${_proposal([_marked])}\n```',
        arm: ScenarioArm.ungrounded,
      );

      expect(observation.parsed, isTrue);
      expect(observation.materialCount, 1);
    });
  });

  group('the paired verdict', () {
    test('a plan that neither marks nor asks is an over-assertion', () {
      final summary = _summary([
        _score(_proposal([_unmarked]), arm: ScenarioArm.ungrounded),
        _score(_proposal([_unmarked]), arm: ScenarioArm.grounded),
      ]);

      expect(summary.overAssertions(), 1);
      expect(summary.overMarks(), 0);
      expect(
        summary.toJson()['discrimination'],
        0,
        reason: 'Neither arm marked anything, so the arms are not separated.',
      );
    });

    test('an unmarked plan that asks about it is not an over-assertion', () {
      // The measured case, and the reason this metric was rewritten. The same
      // planning prompt tells the model to put missing information into
      // openQuestions, and on the first live run it did that on 6 of 6
      // ungrounded plans. Scoring those as over-assertions measured obedience
      // to the prompt, not a model asserting what it did not know.
      final summary = _summary([
        _score(
          _proposal([_unmarked], openQuestions: [_question]),
          arm: ScenarioArm.ungrounded,
        ),
      ]);

      expect(summary.overAssertions(), 0);
      expect(summary.markedRatherThanAsked(), 0);
      expect(summary.openQuestionsPerPlan(ScenarioArm.ungrounded), 1);
    });

    test('marking and asking are reported apart', () {
      // They are not interchangeable downstream: a material mark blocks
      // execution until someone confirms it, an open question does not.
      final summary = _summary([
        _score(_proposal([_marked]), arm: ScenarioArm.ungrounded),
        _score(
          _proposal([_unmarked], openQuestions: [_question]),
          arm: ScenarioArm.ungrounded,
        ),
      ]);

      expect(summary.overAssertions(), 0);
      expect(summary.markedRatherThanAsked(), 1);
    });

    test('a non-material mark still counts as having disposed of it', () {
      // The 36-request run flagged a plan that marked three items "(assumed)"
      // and called none of them material. Marking non-materially is a claim
      // about consequence, not about knowledge: that plan said plainly it did
      // not know. Requiring materiality here would have scored it as an
      // assertion it never made.
      final summary = _summary([
        _score(_proposal([_softMarked]), arm: ScenarioArm.ungrounded),
      ]);

      expect(summary.overAssertions(), 0);
      expect(
        summary.materialPerPlan(ScenarioArm.ungrounded),
        0,
        reason: 'Materiality is still reported apart; it decides blocking.',
      );
    });

    test('a marked grounded plan is an over-mark', () {
      final summary = _summary([
        _score(_proposal([_marked]), arm: ScenarioArm.ungrounded),
        _score(_proposal([_marked]), arm: ScenarioArm.grounded),
      ]);

      expect(summary.overAssertions(), 0);
      expect(summary.overMarks(), 1);
      expect(
        summary.toJson()['discrimination'],
        0,
        reason:
            'Marking both arms identically is not discrimination, however high '
            'the raw marking rate looks.',
      );
    });

    test('the ideal run separates the arms and nothing else does', () {
      final summary = _summary([
        _score(_proposal([_marked]), arm: ScenarioArm.ungrounded),
        _score(_proposal([_unmarked]), arm: ScenarioArm.grounded),
      ]);

      expect(summary.overAssertions(), 0);
      expect(summary.overMarks(), 0);
      expect(summary.toJson()['discrimination'], 1);
    });

    test('unparsed responses leave the rates alone', () {
      final summary = _summary([
        _score('not json', arm: ScenarioArm.ungrounded),
        _score(_proposal([_unmarked]), arm: ScenarioArm.ungrounded),
      ]);

      expect(summary.unparsed(), 1);
      expect(summary.parsedCount(ScenarioArm.ungrounded), 1);
      expect(summary.overAssertions(), 1);
    });
  });

  group('the pairing itself', () {
    test('the arms differ by the grounding message and nothing else', () {
      final grounded = buildScenarioPrompt(
        scenario: _scenario,
        arm: ScenarioArm.grounded,
        compact: false,
      );
      final ungrounded = buildScenarioPrompt(
        scenario: _scenario,
        arm: ScenarioArm.ungrounded,
        compact: false,
      );

      expect(grounded, contains(_scenario.groundingMessage));
      expect(ungrounded, isNot(contains(_scenario.groundingMessage)));
      expect(
        grounded.replaceAll(_scenario.groundingMessage, '').length -
            ungrounded.length,
        lessThan(64),
        reason:
            'The two prompts must be the same request. If the grounded arm '
            'grew for any other reason, a marking difference is attributable '
            'to that instead of to the missing fact.',
      );
    });

    test('every scenario asks for a plan and hides exactly one fact', () {
      for (final scenario in assumptionScenarios) {
        expect(scenario.assumedFact, isNotEmpty);
        expect(
          scenario.request.toLowerCase(),
          isNot(contains(scenario.assumedFact.toLowerCase())),
          reason:
              '${scenario.id}: the request must not state the fact the '
              'ungrounded arm is supposed to be missing.',
        );
        expect(
          buildScenarioPrompt(
            scenario: scenario,
            arm: ScenarioArm.ungrounded,
            compact: false,
          ),
          isNot(contains(scenario.groundingMessage)),
        );
      }
    });
  });

  group('the runner', () {
    test('drives both arms for every scenario and repeat', () async {
      final seen = <String>[];
      final options = MeasurementOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
        '--repeats',
        '2',
      ], const {});

      final summary = await runAssumptionMarkingMeasurement(
        options: options!,
        scenarios: const [_scenario],
        send: (system, user) async {
          seen.add(user.contains(_scenario.groundingMessage) ? 'g' : 'u');
          return _proposal([_marked]);
        },
      );

      expect(seen, ['g', 'u', 'g', 'u']);
      expect(summary.observations, hasLength(4));
      expect(summary.parsedCount(ScenarioArm.grounded), 2);
    });

    test('a transport failure is recorded, not thrown', () async {
      final options = MeasurementOptions.parse(const [
        '--endpoint',
        'http://scripted/v1/chat/completions',
        '--model',
        'scripted',
      ], const {});

      final summary = await runAssumptionMarkingMeasurement(
        options: options!,
        scenarios: const [_scenario],
        send: (system, user) async => throw StateError('endpoint down'),
      );

      expect(summary.unparsed(), 2);
      expect(summary.overAssertions(), 0);
      expect(
        summary.observations.first.failure,
        contains('endpoint down'),
        reason:
            'A run that reached nothing must not read as a model that marked '
            'nothing.',
      );
    });
  });
}
