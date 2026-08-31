import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixturePath = 'tool/fixtures/rag3_offline_hybrid_holdout/fixture.json';
const _oraclePath = 'tool/fixtures/rag3_offline_hybrid_holdout/oracle.json';
const _schemaPath = 'tool/fixtures/rag3_offline_hybrid_holdout/schema.json';

void main() {
  late Map<String, Object?> fixture;
  late Map<String, Object?> oracle;

  setUpAll(() async {
    fixture = _decodeObject(await File(_fixturePath).readAsString());
    oracle = _decodeObject(await File(_oraclePath).readAsString());
  });

  test('freezes fixture identity and corpus content', () async {
    final schema = _decodeObject(await File(_schemaPath).readAsString());
    expect(schema['\$schema'], 'https://json-schema.org/draft/2020-12/schema');
    expect(schema['\$id'], 'caverno://fixtures/rag3-offline-hybrid-holdout/v1');
    expect(_object(schema, '\$defs').keys, containsAll({'fixture', 'oracle'}));
    expect(fixture['schemaName'], 'caverno_rag3_offline_hybrid_fixture');
    expect(fixture['schemaVersion'], 1);
    expect(fixture['schemaId'], schema['\$id']);
    expect(fixture['contractId'], 'rag3-offline-hybrid-eval-contract-v2');
    expect(fixture['fixtureId'], 'rag3-offline-hybrid-holdout-v1');

    final corpusRoot = Directory(
      '${File(_fixturePath).parent.path}/${fixture['corpusRoot']}',
    );
    expect(await _computeCorpusHash(corpusRoot), fixture['corpusHash']);

    final objectIds = <String>{};
    final chunkIds = <String>{};
    for (final object in _objects(fixture, 'objects')) {
      final objectId = _string(object, 'id');
      final sourcePath = _string(object, 'sourcePath');
      expect(objectIds.add(objectId), isTrue, reason: objectId);
      expect(sourcePath, objectId);
      expect(sourcePath, isNot(startsWith('/')));

      final source = File('${corpusRoot.path}/$sourcePath');
      expect(source.existsSync(), isTrue, reason: source.path);
      expect(
        sha256.convert(await source.readAsBytes()).toString(),
        object['objectContentHash'],
        reason: objectId,
      );

      final lines = await source.readAsLines();
      for (final chunk in _objects(object, 'chunks')) {
        final chunkId = _string(chunk, 'id');
        final lineStart = _integer(chunk, 'lineStart');
        final lineEnd = _integer(chunk, 'lineEnd');
        expect(chunkIds.add(chunkId), isTrue, reason: chunkId);
        expect(chunkId, startsWith('$objectId#'));
        expect(lineStart, greaterThan(0));
        expect(lineEnd, inInclusiveRange(lineStart, lines.length));
        final content = lines.sublist(lineStart - 1, lineEnd).join('\n');
        expect(
          sha256.convert(utf8.encode(content)).toString(),
          chunk['contentHash'],
          reason: chunkId,
        );
      }
    }

    expect(objectIds, hasLength(10));
    expect(chunkIds, hasLength(24));
  });

  test('freezes the required 20-case composition', () {
    final cases = _objects(fixture, 'cases');
    final ids = cases.map((item) => _string(item, 'id')).toSet();
    expect(cases, hasLength(20));
    expect(ids, hasLength(20));

    int countStratum(String value) =>
        cases.where((item) => _strings(item, 'strata').contains(value)).length;

    expect(countStratum('answerable'), 14);
    expect(countStratum('unavailable'), 4);
    expect(countStratum('no_search'), 2);
    expect(cases.where((item) => item['language'] == 'ja'), hasLength(4));
    expect(countStratum('expected_abstention'), 2);
    expect(countStratum('topical_only'), 1);
    expect(countStratum('no_evidence'), 1);
    expect(countStratum('current'), greaterThan(0));
    expect(countStratum('historical'), greaterThan(0));
    expect(countStratum('conflict'), greaterThan(0));
    expect(countStratum('safety'), greaterThan(0));
    expect(countStratum('source_diversity'), greaterThan(0));
    expect(countStratum('budget_pressure'), 1);

    for (final item in cases) {
      final shouldSearch = item['shouldSearch'];
      expect(shouldSearch, isA<bool>());
      expect(
        shouldSearch == false,
        _strings(item, 'strata').contains('no_search'),
        reason: _string(item, 'id'),
      );
    }
  });

  test('keeps the complete oracle separate and referentially valid', () {
    expect(oracle['schemaName'], 'caverno_rag3_offline_hybrid_oracle');
    expect(oracle['schemaVersion'], 1);
    expect(oracle['schemaId'], fixture['schemaId']);
    expect(oracle['contractId'], fixture['contractId']);
    expect(oracle['fixtureId'], fixture['fixtureId']);
    expect(oracle['corpusHash'], fixture['corpusHash']);
    expect(oracle['defaultPassageRole'], 'irrelevant');

    final fixtureCases = {
      for (final item in _objects(fixture, 'cases')) _string(item, 'id'): item,
    };
    final objectIds = <String>{};
    final chunkIds = <String>{};
    for (final object in _objects(fixture, 'objects')) {
      objectIds.add(_string(object, 'id'));
      chunkIds.addAll(
        _objects(object, 'chunks').map((item) => _string(item, 'id')),
      );
    }

    final oracleCases = _objects(oracle, 'cases');
    expect(
      oracleCases.map((item) => _string(item, 'id')).toSet(),
      fixtureCases.keys.toSet(),
    );

    const allowedRoles = {
      'answer_support',
      'abstention_support',
      'topical_only',
      'irrelevant',
    };
    final expectedRoleCounts = <String, int>{};
    for (final item in oracleCases) {
      final id = _string(item, 'id');
      final expectedRole = _string(item, 'expectedEvidenceRole');
      expectedRoleCounts.update(
        expectedRole,
        (value) => value + 1,
        ifAbsent: () => 1,
      );

      final qrels = _object(item, 'qrels');
      final objectQrels = _object(qrels, 'objects');
      final chunkQrels = _object(qrels, 'chunks');
      expect(objectQrels.keys, everyElement(isIn(objectIds)), reason: id);
      expect(chunkQrels.keys, everyElement(isIn(chunkIds)), reason: id);

      final roles = _object(item, 'passageRoles');
      expect(roles.keys, everyElement(isIn(chunkIds)), reason: id);
      expect(roles.values, everyElement(isIn(allowedRoles)), reason: id);

      if (fixtureCases[id]!['shouldSearch'] == false) {
        expect(objectQrels, isEmpty, reason: id);
        expect(chunkQrels, isEmpty, reason: id);
        expect(roles, isEmpty, reason: id);
      }
    }

    expect(expectedRoleCounts, {
      'answer_support': 14,
      'abstention_support': 2,
      'topical_only': 1,
      'no_evidence': 1,
      'not_applicable': 2,
    });
  });

  test(
    'contains deterministic merge, diversity, and budget pressure',
    () async {
      final policy = _object(fixture, 'selectionPolicy');
      expect(policy, {
        'contextBudgetTokens': 6000,
        'maxGroupsPerObject': 2,
        'estimatedRunesPerToken': 4,
        'citationFormatVersion': 'rag3-citation-v1',
      });

      final objects = {
        for (final item in _objects(fixture, 'objects'))
          _string(item, 'id'): item,
      };
      final recoveryChunks = _objects(
        objects['docs/recovery_runbook.md']!,
        'chunks',
      );
      expect(recoveryChunks, hasLength(4));
      expect(
        _integer(recoveryChunks[0], 'lineEnd'),
        _integer(recoveryChunks[1], 'lineStart') - 1,
      );
      expect(
        _integer(recoveryChunks[2], 'lineStart'),
        greaterThan(_integer(recoveryChunks[1], 'lineEnd') + 1),
      );
      expect(
        _integer(recoveryChunks[3], 'lineStart'),
        greaterThan(_integer(recoveryChunks[2], 'lineEnd') + 1),
      );

      final primary = await _chunkCost(
        fixture,
        objects['docs/budget_primary.md']!,
        _objects(objects['docs/budget_primary.md']!, 'chunks').single,
      );
      final tail = await _chunkCost(
        fixture,
        objects['docs/budget_tail.md']!,
        _objects(objects['docs/budget_tail.md']!, 'chunks').single,
      );
      expect(primary, lessThan(6000));
      expect(primary + tail, greaterThan(6000));
    },
  );

  test('contains no candidate run outputs', () {
    const forbiddenKeys = {
      'lexicalRanking',
      'vectorRanking',
      'rankedChunkIds',
      'fusedScores',
      'selectedGroups',
      'exclusions',
      'latency',
      'resourceMeasurements',
      'vectorAvailability',
      'vectorValidationReceipt',
      'results',
    };
    expect(_findForbiddenKeys(fixture, forbiddenKeys), isEmpty);
    expect(_findForbiddenKeys(oracle, forbiddenKeys), isEmpty);
  });
}

Future<String> _computeCorpusHash(Directory root) async {
  final sorted =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final bytes = <int>[];
  for (final file in sorted) {
    bytes
      ..addAll(utf8.encode(file.path.substring(root.path.length + 1)))
      ..add(0)
      ..addAll(await file.readAsBytes())
      ..add(0);
  }
  return sha256.convert(bytes).toString();
}

Future<int> _chunkCost(
  Map<String, Object?> fixture,
  Map<String, Object?> object,
  Map<String, Object?> chunk,
) async {
  final root = File(_fixturePath).parent.path;
  final source = File('$root/${fixture['corpusRoot']}/${object['sourcePath']}');
  final lines = await source.readAsLines();
  final start = _integer(chunk, 'lineStart');
  final end = _integer(chunk, 'lineEnd');
  final content = lines.sublist(start - 1, end).join('\n');
  final citation =
      '[source=${object['sourcePath']}; revision=${object['revision']}; '
      'lines=$start-$end; object_sha256=${object['objectContentHash']}; '
      'chunk_sha256=${chunk['contentHash']}]';
  return (content.runes.length + citation.runes.length + 3) ~/ 4;
}

Set<String> _findForbiddenKeys(Object? value, Set<String> forbidden) {
  final found = <String>{};
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is String && forbidden.contains(entry.key)) {
        found.add(entry.key as String);
      }
      found.addAll(_findForbiddenKeys(entry.value, forbidden));
    }
  } else if (value is List) {
    for (final item in value) {
      found.addAll(_findForbiddenKeys(item, forbidden));
    }
  }
  return found;
}

Map<String, Object?> _decodeObject(String source) =>
    (jsonDecode(source) as Map).cast<String, Object?>();

Map<String, Object?> _object(Map<String, Object?> source, String key) =>
    (source[key] as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Map<String, Object?> source, String key) =>
    (source[key] as List)
        .map((item) => (item as Map).cast<String, Object?>())
        .toList(growable: false);

List<String> _strings(Map<String, Object?> source, String key) =>
    (source[key] as List).cast<String>();

String _string(Map<String, Object?> source, String key) =>
    source[key] as String;

int _integer(Map<String, Object?> source, String key) => source[key] as int;
