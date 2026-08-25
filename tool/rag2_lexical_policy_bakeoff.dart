import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import 'rag_retrieval_baseline.dart';
import 'rag_retrieval_eval.dart';

const rag2LexicalBakeoffSchema = 'caverno_rag2_lexical_policy_bakeoff';
const rag2LexicalBakeoffSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = Rag2LexicalBakeoffOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/rag2_lexical_policy_bakeoff.dart '
      '--fixture PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }
  try {
    final report = await runRag2LexicalBakeoff(options);
    stdout.writeln(report.toMarkdown());
  } on Object catch (error) {
    stderr.writeln('RAG2 lexical policy bake-off failed: $error');
    exitCode = 65;
  }
}

Future<Rag2LexicalBakeoffReport> runRag2LexicalBakeoff(
  Rag2LexicalBakeoffOptions options,
) async {
  final fixture = await RagRetrievalFixture.load(File(options.fixturePath));
  fixture.validate();
  final documents = await loadRagFixtureDocuments(fixture);
  final candidates = <Rag2LexicalCandidateResult>[];
  for (final policy in Rag2LexicalPolicy.values) {
    final scorer = Rag2LexicalScorer(policy: policy, documents: documents);
    try {
      final rankedCases = [
        for (final fixtureCase in fixture.cases)
          scorer.rank(fixtureCase.query, limit: documents.length),
      ];
      for (final threshold in rag2LexicalThresholds) {
        candidates.add(
          evaluateRag2LexicalCandidate(
            fixture: fixture,
            policy: policy,
            threshold: threshold,
            rankedCases: rankedCases,
          ),
        );
      }
    } finally {
      scorer.close();
    }
  }
  candidates.sort(compareRag2LexicalCandidates);
  final report = Rag2LexicalBakeoffReport(
    fixtureId: fixture.fixtureId,
    corpusHash: await fixture.computeCorpusHash(),
    candidates: candidates,
  );
  final outputDirectory = Directory(options.outDir);
  await outputDirectory.create(recursive: true);
  await File(
    '${outputDirectory.path}/rag2_lexical_policy_bakeoff.json',
  ).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  await File(
    '${outputDirectory.path}/rag2_lexical_policy_bakeoff.md',
  ).writeAsString(report.toMarkdown());
  return report;
}

const rag2LexicalThresholds = <double>[
  0.05,
  0.10,
  0.15,
  0.20,
  0.25,
  0.30,
  0.35,
  0.40,
  0.50,
  0.60,
  0.70,
  0.80,
  0.90,
];

enum Rag2LexicalPolicy {
  word,
  bigram,
  trigram;

  String get id => switch (this) {
    word => 'word_or_idf',
    bigram => 'bigram_or_idf',
    trigram => 'trigram_or_idf',
  };
}

final class Rag2LexicalScorer {
  Rag2LexicalScorer({required this.policy, required this.documents})
    : documentTerms = [
        for (final document in documents)
          tokenizeRag2Lexical(document.content, policy),
      ],
      documentFrequency = _documentFrequency([
        for (final document in documents)
          tokenizeRag2Lexical(document.content, policy),
      ]) {
    database.execute(
      'CREATE VIRTUAL TABLE knowledge USING fts5('
      'object_id UNINDEXED, content, tokenize=unicode61)',
    );
    for (var index = 0; index < documents.length; index++) {
      database.execute(
        'INSERT INTO knowledge(object_id, content) VALUES (?, ?)',
        [documents[index].objectId, documentTerms[index].join(' ')],
      );
    }
  }

  final Rag2LexicalPolicy policy;
  final List<RagFixtureDocument> documents;
  final List<Set<String>> documentTerms;
  final Map<String, int> documentFrequency;
  final Database database = sqlite3.openInMemory();

  List<Rag2LexicalHit> rank(String query, {required int limit}) {
    final queryTerms = tokenizeRag2Lexical(query, policy);
    if (queryTerms.isEmpty) return const [];
    final denominator = queryTerms.fold<double>(
      0,
      (sum, term) => sum + _idf(term),
    );
    final matchQuery = queryTerms
        .map((term) => '"${term.replaceAll('"', '""')}"')
        .join(' OR ');
    final rows = database.select(
      'SELECT object_id, bm25(knowledge) AS rank FROM knowledge '
      'WHERE knowledge MATCH ? '
      'ORDER BY bm25(knowledge), object_id LIMIT ?',
      [matchQuery, limit],
    );
    final hits = <Rag2LexicalHit>[];
    for (final row in rows) {
      final index = documents.indexWhere(
        (item) => item.objectId == row['object_id'],
      );
      final overlap = queryTerms.intersection(documentTerms[index]);
      final score =
          overlap.fold<double>(0, (sum, term) => sum + _idf(term)) /
          denominator;
      final segmentScore = _bestSegmentCoverage(
        queryTerms,
        documents[index].content,
        denominator,
      );
      hits.add(
        Rag2LexicalHit(
          objectId: documents[index].objectId,
          chunkId: documents[index].chunkId,
          score: score,
          segmentScore: segmentScore,
          bm25Relevance: -(row['rank'] as num).toDouble(),
        ),
      );
    }
    return hits;
  }

  void close() => database.close();

  double _idf(String term) =>
      math.log((documents.length + 1) / ((documentFrequency[term] ?? 0) + 1)) +
      1;

  double _bestSegmentCoverage(
    Set<String> queryTerms,
    String content,
    double denominator,
  ) {
    var best = 0.0;
    for (final segment in content.split(RegExp(r'[\n.!?]+'))) {
      final terms = tokenizeRag2Lexical(segment, policy);
      final overlap = queryTerms.intersection(terms);
      final score =
          overlap.fold<double>(0, (sum, term) => sum + _idf(term)) /
          denominator;
      if (score > best) best = score;
    }
    return best;
  }
}

Set<String> tokenizeRag2Lexical(String source, Rag2LexicalPolicy policy) {
  final normalized = source.toLowerCase();
  final runs = RegExp(
    r'[\p{L}\p{N}_]+',
    unicode: true,
  ).allMatches(normalized).map((match) => match.group(0)!).toList();
  if (policy == Rag2LexicalPolicy.word) return runs.toSet();
  final width = policy == Rag2LexicalPolicy.bigram ? 2 : 3;
  final terms = <String>{};
  for (final run in runs) {
    final characters = run.runes.toList();
    if (characters.length < width) {
      terms.add(run);
      continue;
    }
    for (var index = 0; index <= characters.length - width; index++) {
      terms.add(String.fromCharCodes(characters.sublist(index, index + width)));
    }
  }
  return terms;
}

Map<String, int> _documentFrequency(List<Set<String>> documents) {
  final frequency = <String, int>{};
  for (final document in documents) {
    for (final term in document) {
      frequency.update(term, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return frequency;
}

Rag2LexicalCandidateResult evaluateRag2LexicalCandidate({
  required RagRetrievalFixture fixture,
  required Rag2LexicalPolicy policy,
  required double threshold,
  required List<List<Rag2LexicalHit>> rankedCases,
}) {
  var answerableHits = 0;
  var noAnswerRetrieved = 0;
  var reciprocalRankTotal = 0.0;
  final category = <String, Rag2LexicalBreakdown>{};
  final authority = <String, Rag2LexicalBreakdown>{};
  final cases = <Rag2LexicalCaseResult>[];
  for (var index = 0; index < fixture.cases.length; index++) {
    final fixtureCase = fixture.cases[index];
    final hits = rankedCases[index]
        .where((hit) => hit.score >= threshold)
        .take(fixture.metricK)
        .toList();
    final firstRelevant = hits.indexWhere(
      (hit) => fixtureCase.objectRelevance.containsKey(hit.objectId),
    );
    final answerable = fixtureCase.objectRelevance.isNotEmpty;
    final hit = firstRelevant >= 0;
    if (answerable && hit) {
      answerableHits++;
      reciprocalRankTotal += 1 / (firstRelevant + 1);
    }
    if (!answerable && hits.isNotEmpty) noAnswerRetrieved++;
    cases.add(
      Rag2LexicalCaseResult(
        caseId: fixtureCase.id,
        category: fixtureCase.category,
        authority: fixtureCase.authority,
        topScore: hits.isEmpty ? null : hits.first.score,
        returnedHitCount: hits.length,
        relevantRank: firstRelevant < 0 ? null : firstRelevant + 1,
      ),
    );
    category.update(
      fixtureCase.category,
      (value) => value.add(
        answerable: answerable,
        hit: hit,
        retrieved: hits.isNotEmpty,
      ),
      ifAbsent: () => Rag2LexicalBreakdown.single(
        answerable: answerable,
        hit: hit,
        retrieved: hits.isNotEmpty,
      ),
    );
    authority.update(
      fixtureCase.authority,
      (value) => value.add(
        answerable: answerable,
        hit: hit,
        retrieved: hits.isNotEmpty,
      ),
      ifAbsent: () => Rag2LexicalBreakdown.single(
        answerable: answerable,
        hit: hit,
        retrieved: hits.isNotEmpty,
      ),
    );
  }
  return Rag2LexicalCandidateResult(
    policy: policy,
    threshold: threshold,
    answerableHits: answerableHits,
    noAnswerRetrieved: noAnswerRetrieved,
    mrr: reciprocalRankTotal / 16,
    category: category,
    authority: authority,
    cases: cases,
  );
}

int compareRag2LexicalCandidates(
  Rag2LexicalCandidateResult left,
  Rag2LexicalCandidateResult right,
) {
  final gate = (right.meetsSpikeGate ? 1 : 0).compareTo(
    left.meetsSpikeGate ? 1 : 0,
  );
  if (gate != 0) return gate;
  final hits = right.answerableHits.compareTo(left.answerableHits);
  if (hits != 0) return hits;
  final falsePositives = left.noAnswerRetrieved.compareTo(
    right.noAnswerRetrieved,
  );
  if (falsePositives != 0) return falsePositives;
  final mrr = right.mrr.compareTo(left.mrr);
  if (mrr != 0) return mrr;
  final policy = left.policy.index.compareTo(right.policy.index);
  return policy != 0 ? policy : right.threshold.compareTo(left.threshold);
}

final class Rag2LexicalHit {
  const Rag2LexicalHit({
    required this.objectId,
    required this.chunkId,
    required this.score,
    required this.segmentScore,
    required this.bm25Relevance,
  });

  final String objectId;
  final String chunkId;
  final double score;
  final double segmentScore;
  final double bm25Relevance;
}

final class Rag2LexicalCandidateResult {
  const Rag2LexicalCandidateResult({
    required this.policy,
    required this.threshold,
    required this.answerableHits,
    required this.noAnswerRetrieved,
    required this.mrr,
    required this.category,
    required this.authority,
    required this.cases,
  });

  final Rag2LexicalPolicy policy;
  final double threshold;
  final int answerableHits;
  final int noAnswerRetrieved;
  final double mrr;
  final Map<String, Rag2LexicalBreakdown> category;
  final Map<String, Rag2LexicalBreakdown> authority;
  final List<Rag2LexicalCaseResult> cases;

  bool get meetsSpikeGate => answerableHits >= 15 && noAnswerRetrieved <= 1;

  Map<String, Object?> toJson() => {
    'policy': policy.id,
    'threshold': threshold,
    'answerableHits': answerableHits,
    'answerableCases': 16,
    'noAnswerRetrieved': noAnswerRetrieved,
    'noAnswerCases': 4,
    'mrrAt5': mrr,
    'meetsSpikeGate': meetsSpikeGate,
    'category': category.map((key, value) => MapEntry(key, value.toJson())),
    'authority': authority.map((key, value) => MapEntry(key, value.toJson())),
    'cases': [for (final item in cases) item.toJson()],
  };
}

final class Rag2LexicalCaseResult {
  const Rag2LexicalCaseResult({
    required this.caseId,
    required this.category,
    required this.authority,
    required this.topScore,
    required this.returnedHitCount,
    required this.relevantRank,
  });

  final String caseId;
  final String category;
  final String authority;
  final double? topScore;
  final int returnedHitCount;
  final int? relevantRank;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'category': category,
    'authority': authority,
    'topScore': topScore,
    'returnedHitCount': returnedHitCount,
    'relevantRank': relevantRank,
  };
}

final class Rag2LexicalBreakdown {
  const Rag2LexicalBreakdown({
    required this.cases,
    required this.answerableCases,
    required this.hits,
    required this.retrievedCases,
  });

  factory Rag2LexicalBreakdown.single({
    required bool answerable,
    required bool hit,
    required bool retrieved,
  }) => Rag2LexicalBreakdown(
    cases: 1,
    answerableCases: answerable ? 1 : 0,
    hits: hit ? 1 : 0,
    retrievedCases: retrieved ? 1 : 0,
  );

  final int cases;
  final int answerableCases;
  final int hits;
  final int retrievedCases;

  Rag2LexicalBreakdown add({
    required bool answerable,
    required bool hit,
    required bool retrieved,
  }) => Rag2LexicalBreakdown(
    cases: cases + 1,
    answerableCases: answerableCases + (answerable ? 1 : 0),
    hits: hits + (hit ? 1 : 0),
    retrievedCases: retrievedCases + (retrieved ? 1 : 0),
  );

  Map<String, Object?> toJson() => {
    'cases': cases,
    'answerableCases': answerableCases,
    'hits': hits,
    'retrievedCases': retrievedCases,
  };
}

final class Rag2LexicalBakeoffReport {
  const Rag2LexicalBakeoffReport({
    required this.fixtureId,
    required this.corpusHash,
    required this.candidates,
  });

  final String fixtureId;
  final String corpusHash;
  final List<Rag2LexicalCandidateResult> candidates;
  Rag2LexicalCandidateResult get winner => candidates.first;

  Map<String, Object?> toJson() => {
    'schemaName': rag2LexicalBakeoffSchema,
    'schemaVersion': rag2LexicalBakeoffSchemaVersion,
    'fixtureId': fixtureId,
    'corpusHash': corpusHash,
    'selectionPolicy': 'gate_then_hits_then_false_positives_then_mrr_v1',
    'spikeGate': {'minimumAnswerableHits': 15, 'maximumNoAnswerRetrieved': 1},
    'winner': winner.toJson(),
    'candidates': [for (final candidate in candidates) candidate.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RAG2 Lexical Policy Bake-off')
      ..writeln()
      ..writeln('- Fixture: `$fixtureId`')
      ..writeln('- Corpus SHA-256: `$corpusHash`')
      ..writeln(
        '- Candidate-only result: `${winner.meetsSpikeGate ? 'go' : 'no_go'}`',
      )
      ..writeln(
        '- Winner: `${winner.policy.id}` at `${winner.threshold.toStringAsFixed(2)}`',
      )
      ..writeln()
      ..writeln(
        '| Rank | Policy | Threshold | Answerable hits | No-answer retrieved | MRR@5 | Gate |',
      )
      ..writeln('| ---: | --- | ---: | ---: | ---: | ---: | --- |');
    for (var index = 0; index < math.min(10, candidates.length); index++) {
      final candidate = candidates[index];
      buffer.writeln(
        '| ${index + 1} | ${candidate.policy.id} | '
        '${candidate.threshold.toStringAsFixed(2)} | '
        '${candidate.answerableHits}/16 | '
        '${candidate.noAnswerRetrieved}/4 | '
        '${candidate.mrr.toStringAsFixed(3)} | '
        '${candidate.meetsSpikeGate ? 'pass' : 'fail'} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Winner case diagnostics')
      ..writeln()
      ..writeln('| Case | Authority | Top score | Hits | Relevant rank |')
      ..writeln('| --- | --- | ---: | ---: | ---: |');
    for (final item in winner.cases) {
      buffer.writeln(
        '| ${item.caseId} | ${item.authority} | '
        '${item.topScore?.toStringAsFixed(3) ?? 'none'} | '
        '${item.returnedHitCount} | ${item.relevantRank ?? 'none'} |',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'This is a seed-calibrated in-memory FTS5 policy spike, not a production gate. A holdout corpus and production-schema integration remain required before migration work.',
      );
    return buffer.toString();
  }
}

final class Rag2LexicalBakeoffOptions {
  const Rag2LexicalBakeoffOptions({
    required this.fixturePath,
    required this.outDir,
  });

  final String fixturePath;
  final String outDir;

  static Rag2LexicalBakeoffOptions? parse(List<String> args) {
    if (args.length != 4) return null;
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (!args[index].startsWith('--')) return null;
      values[args[index]] = args[index + 1];
    }
    final fixture = values['--fixture'];
    final outDir = values['--out-dir'];
    if (fixture == null || outDir == null || values.length != 2) return null;
    return Rag2LexicalBakeoffOptions(fixturePath: fixture, outDir: outDir);
  }
}
