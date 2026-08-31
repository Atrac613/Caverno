import 'dart:convert';

const rag3EvidenceRoleClassifierSchema =
    'caverno_rag3_evidence_role_classifier_report';
const rag3EvidenceRoleClassifierContract = 'rag3-evidence-role-classifier-v1';
const rag3EvidenceRoleMinimumMacroF1 = 0.90;
const rag3EvidenceRoleMinimumClassF1 = 0.85;

enum Rag3RuntimeEvidenceRole {
  answerSupport('answer_support'),
  abstentionSupport('abstention_support'),
  topicalOnly('topical_only'),
  irrelevant('irrelevant');

  const Rag3RuntimeEvidenceRole(this.id);

  final String id;

  static Rag3RuntimeEvidenceRole parse(String value) => values.singleWhere(
    (item) => item.id == value,
    orElse: () =>
        throw FormatException('Unsupported RAG3 runtime evidence role: $value'),
  );
}

final class Rag3EvidenceRoleClassifierInput {
  Rag3EvidenceRoleClassifierInput({
    required this.query,
    required this.sourcePath,
    required this.revision,
    required this.authority,
    required this.content,
  }) {
    if (query.trim().isEmpty ||
        sourcePath.trim().isEmpty ||
        revision.trim().isEmpty ||
        authority.trim().isEmpty ||
        content.trim().isEmpty) {
      throw StateError('RAG3 evidence-role classifier inputs cannot be empty.');
    }
    if (sourcePath.startsWith('/') ||
        sourcePath.contains('\\') ||
        sourcePath.split('/').contains('..') ||
        Uri.parse(sourcePath).hasScheme) {
      throw StateError(
        'RAG3 evidence-role classifier source paths must be relative.',
      );
    }
    if (isRag3PromotionArtifactPath(sourcePath)) {
      throw StateError(
        'RAG3 evidence-role classifier inputs cannot use promotion artifacts.',
      );
    }
  }

  final String query;
  final String sourcePath;
  final String revision;
  final String authority;
  final String content;

  Map<String, Object?> toClassifierJson() => {
    'contract': rag3EvidenceRoleClassifierContract,
    'query': query,
    'evidence': {
      'sourcePath': sourcePath,
      'revision': revision,
      'authority': authority,
      'content': content,
    },
    'roles': {
      'answer_support':
          'The evidence directly supports an answer to the requested fact.',
      'abstention_support':
          'The evidence supports a bounded negative or explains that the requested fact cannot be supplied.',
      'topical_only':
          'The evidence concerns the topic but does not support an answer or bounded abstention.',
      'irrelevant':
          'The evidence is unrelated or would mislead an answer to the query.',
    },
    'output': {'schemaVersion': 1, 'role': '<one role key>'},
  };
}

abstract interface class Rag3EvidenceRoleClassifier {
  Future<String> classify(Rag3EvidenceRoleClassifierInput input);
}

final class Rag3EvidenceRoleClassifierUnavailable implements Exception {
  const Rag3EvidenceRoleClassifierUnavailable();
}

enum Rag3EvidenceRolePredictionStatus { available, notAvailable, invalid }

final class Rag3EvidenceRolePrediction {
  const Rag3EvidenceRolePrediction({
    required this.status,
    required this.role,
    required this.reason,
  });

  factory Rag3EvidenceRolePrediction.parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException(
        'RAG3 evidence-role response must be a JSON object.',
      );
    }
    final json = decoded.cast<String, Object?>();
    if (json.keys.toSet().difference(const {
          'schemaVersion',
          'role',
        }).isNotEmpty ||
        json.length != 2 ||
        json['schemaVersion'] != 1 ||
        json['role'] is! String) {
      throw const FormatException(
        'RAG3 evidence-role response must match the exact v1 schema.',
      );
    }
    return Rag3EvidenceRolePrediction(
      status: Rag3EvidenceRolePredictionStatus.available,
      role: Rag3RuntimeEvidenceRole.parse(json['role']! as String),
      reason: 'classified',
    );
  }

  const Rag3EvidenceRolePrediction.failClosed({
    required Rag3EvidenceRolePredictionStatus status,
    required String reason,
  }) : this(
         status: status,
         role: Rag3RuntimeEvidenceRole.irrelevant,
         reason: reason,
       );

  final Rag3EvidenceRolePredictionStatus status;
  final Rag3RuntimeEvidenceRole role;
  final String reason;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'role': role.id,
    'reason': reason,
  };
}

final class Rag3EvidenceRoleInstrumentExample {
  const Rag3EvidenceRoleInstrumentExample({
    required this.caseId,
    required this.chunkId,
    required this.input,
    required this.expectedRole,
  });

  final String caseId;
  final String chunkId;
  final Rag3EvidenceRoleClassifierInput input;
  final Rag3RuntimeEvidenceRole expectedRole;
}

Future<Rag3EvidenceRoleClassifierReport> evaluateRag3EvidenceRoleClassifier({
  required String fixtureId,
  required List<Rag3EvidenceRoleInstrumentExample> examples,
  required Rag3EvidenceRoleClassifier classifier,
}) async {
  if (fixtureId.trim().isEmpty || examples.isEmpty) {
    throw StateError('RAG3 evidence-role evaluation requires a fixture.');
  }
  if (isRag3PromotionArtifactPath(fixtureId)) {
    throw StateError(
      'RAG3 evidence-role evaluation cannot use promotion artifacts.',
    );
  }
  final identities = <String>{};
  for (final example in examples) {
    if (!identities.add('${example.caseId}\u0000${example.chunkId}')) {
      throw StateError('RAG3 evidence-role examples must be unique.');
    }
  }
  final expectedRoles = examples.map((item) => item.expectedRole).toSet();
  if (!expectedRoles.containsAll(Rag3RuntimeEvidenceRole.values)) {
    throw StateError(
      'RAG3 evidence-role evaluation must cover all four role classes.',
    );
  }
  final results = <Rag3EvidenceRoleCaseResult>[];
  for (final example in examples) {
    late final Rag3EvidenceRolePrediction prediction;
    try {
      prediction = Rag3EvidenceRolePrediction.parse(
        await classifier.classify(example.input),
      );
    } on Rag3EvidenceRoleClassifierUnavailable {
      prediction = const Rag3EvidenceRolePrediction.failClosed(
        status: Rag3EvidenceRolePredictionStatus.notAvailable,
        reason: 'classifier_not_available',
      );
    } on FormatException {
      prediction = const Rag3EvidenceRolePrediction.failClosed(
        status: Rag3EvidenceRolePredictionStatus.invalid,
        reason: 'invalid_classifier_response',
      );
    }
    results.add(
      Rag3EvidenceRoleCaseResult(
        caseId: example.caseId,
        chunkId: example.chunkId,
        expectedRole: example.expectedRole,
        prediction: prediction,
      ),
    );
  }
  return Rag3EvidenceRoleClassifierReport(
    fixtureId: fixtureId,
    cases: List.unmodifiable(results),
  );
}

final class Rag3EvidenceRoleCaseResult {
  const Rag3EvidenceRoleCaseResult({
    required this.caseId,
    required this.chunkId,
    required this.expectedRole,
    required this.prediction,
  });

  final String caseId;
  final String chunkId;
  final Rag3RuntimeEvidenceRole expectedRole;
  final Rag3EvidenceRolePrediction prediction;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'chunkId': chunkId,
    'expectedRole': expectedRole.id,
    'prediction': prediction.toJson(),
  };
}

final class Rag3EvidenceRoleClassMetrics {
  const Rag3EvidenceRoleClassMetrics({
    required this.truePositive,
    required this.falsePositive,
    required this.falseNegative,
  });

  final int truePositive;
  final int falsePositive;
  final int falseNegative;

  double get precision => truePositive + falsePositive == 0
      ? 0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);

  Map<String, Object?> toJson() => {
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'precision': precision,
    'recall': recall,
    'f1': f1,
  };
}

final class Rag3EvidenceRoleClassifierReport {
  const Rag3EvidenceRoleClassifierReport({
    required this.fixtureId,
    required this.cases,
  });

  final String fixtureId;
  final List<Rag3EvidenceRoleCaseResult> cases;

  Map<Rag3RuntimeEvidenceRole, Rag3EvidenceRoleClassMetrics> get metrics => {
    for (final role in Rag3RuntimeEvidenceRole.values)
      role: Rag3EvidenceRoleClassMetrics(
        truePositive: cases
            .where(
              (item) =>
                  item.expectedRole == role && item.prediction.role == role,
            )
            .length,
        falsePositive: cases
            .where(
              (item) =>
                  item.expectedRole != role && item.prediction.role == role,
            )
            .length,
        falseNegative: cases
            .where(
              (item) =>
                  item.expectedRole == role && item.prediction.role != role,
            )
            .length,
      ),
  };

  double get macroF1 =>
      metrics.values.fold<double>(0, (sum, item) => sum + item.f1) /
      Rag3RuntimeEvidenceRole.values.length;
  int get unavailableCount => cases
      .where(
        (item) =>
            item.prediction.status ==
            Rag3EvidenceRolePredictionStatus.notAvailable,
      )
      .length;
  int get invalidCount => cases
      .where(
        (item) =>
            item.prediction.status == Rag3EvidenceRolePredictionStatus.invalid,
      )
      .length;
  bool get passed =>
      unavailableCount == 0 &&
      invalidCount == 0 &&
      macroF1 >= rag3EvidenceRoleMinimumMacroF1 &&
      metrics.values.every((item) => item.f1 >= rag3EvidenceRoleMinimumClassF1);

  Map<String, Object?> toJson() => {
    'schemaName': rag3EvidenceRoleClassifierSchema,
    'schemaVersion': 1,
    'contract': rag3EvidenceRoleClassifierContract,
    'fixtureId': fixtureId,
    'result': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'promotionDecision': 'not_run',
    'macroF1': macroF1,
    'minimumMacroF1': rag3EvidenceRoleMinimumMacroF1,
    'minimumClassF1': rag3EvidenceRoleMinimumClassF1,
    'unavailableCount': unavailableCount,
    'invalidCount': invalidCount,
    'metrics': {
      for (final entry in metrics.entries) entry.key.id: entry.value.toJson(),
    },
    'cases': [for (final item in cases) item.toJson()],
  };
}

bool isRag3PromotionArtifactPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.contains('rag3_offline_hybrid_holdout') ||
      normalized.contains('rag3_promotion');
}
