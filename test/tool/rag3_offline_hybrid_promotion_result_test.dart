import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _resultPath = 'tool/fixtures/rag3_offline_hybrid_promotion_result.json';

void main() {
  late String encoded;
  late Map<String, Object?> result;

  setUpAll(() async {
    encoded = await File(_resultPath).readAsString();
    result = (jsonDecode(encoded) as Map).cast<String, Object?>();
  });

  test('freezes the privacy-safe one-shot promotion identity', () {
    expect(
      sha256.convert(utf8.encode(encoded)).toString(),
      '06643c3ea96d8a1667c8fd8c522dc2ae3baaf4bf663461977828d4ef886e8df4',
    );
    expect(
      result['schemaName'],
      'caverno_rag3_offline_hybrid_promotion_result',
    );
    expect(result['schemaVersion'], 1);
    expect(result['contractId'], 'rag3-offline-hybrid-eval-contract-v2');
    expect(result['candidateId'], 'rrf-k60-l1-v1-budget6000-v1');
    expect(result['fixtureId'], 'rag3-offline-hybrid-holdout-v1');
    expect(
      result['corpusHash'],
      '6a126fadf7358fc3209cf0dec71a72d4834b398c7bc16e592769d0c7990e49ad',
    );
    expect(result['runId'], 'rag3-promotion-run-v1');
    expect(result['buildCommit'], '1127597bf3af4fc4719bba131730509878d00ce8');
    expect(result['sourceArtifacts'], {
      'reportSha256':
          '6b7d8a41331b3eb28f9ff4bf71cc1cc1194423521ef776d2d18391978304854c',
      'runSha256':
          'b94e83a298c7fd3192ed3825188354c395d72b28ada642f1792e32fd477c58f2',
    });
    expect(encoded, isNot(contains('http://')));
    expect(encoded, isNot(contains('https://')));
    expect(encoded, isNot(contains('endpointIdentity')));
    expect(encoded, isNot(contains('rankedChunkIds')));
    expect(encoded, isNot(contains('selectedGroups')));
    expect(encoded, isNot(contains('"query"')));
  });

  test('pins the No-Go aggregate and sole failing case', () {
    expect(result['result'], 'no_go');
    expect(result['deterministicReplayPassed'], isTrue);
    expect(result['arms'], {
      'lexical': {
        'objectRecallAt10': 0.6785714285714286,
        'objectHitAt5': 0.7142857142857143,
        'objectMrrAt10': 0.7142857142857143,
      },
      'vector': {
        'objectRecallAt10': 0.9642857142857143,
        'objectHitAt5': 1.0,
        'objectMrrAt10': 0.8928571428571429,
      },
      'hybrid': {
        'objectRecallAt10': 0.9642857142857143,
        'objectHitAt5': 1.0,
        'objectMrrAt10': 0.9285714285714286,
      },
    });
    expect(result['support'], {
      'answer': {'retrieved': 14, 'cases': 14},
      'japaneseAnswer': {'retrieved': 4, 'cases': 4},
      'abstention': {'retrieved': 2, 'cases': 2},
      'unavailableIrrelevantOnly': 1,
    });
    expect(result['betterArmMissCount'], 0);
    expect(result['noSearchRetrievalCount'], 0);
    expect(result['contextBudgetViolationCount'], 0);
    expect(result['provenanceViolationCount'], 0);
    expect(result['failingCases'], ['unavailable-weather']);
    expect(result['gates'], {
      'objectRecallAt10': true,
      'objectHitAt5': true,
      'objectMrrAt10': true,
      'hybridBetterArmMisses': true,
      'answerSupport': true,
      'japaneseAnswerSupport': true,
      'abstentionSupport': true,
      'unavailableIrrelevantOnly': false,
      'contextBudget': true,
      'noSearch': true,
      'citationAndProvenance': true,
      'emptyFusionNegativeControl': true,
      'budgetBypassNegativeControl': true,
      'vectorDegradation': true,
    });
  });
}
