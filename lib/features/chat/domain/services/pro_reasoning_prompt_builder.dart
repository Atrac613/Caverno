import 'dart:convert';

import 'pro_reasoning_models.dart';

final class ProReasoningPromptBuilder {
  const ProReasoningPromptBuilder();

  String buildFramePrompt(String question) =>
      '''
You are framing one expensive, high-quality reasoning run. Decompose the user
question without answering it. Return one JSON object and no prose:
{
  "sub_questions": ["..."],
  "investigation_steps": ["..."],
  "success_criteria": ["..."],
  "requires_investigation": true
}

Use at most five items in each list. Set requires_investigation only when fresh
facts, linked sources, or local file evidence would materially improve the
answer.

User question:
$question
'''
          .trim();

  ProReasoningFrame parseFrame(String raw, String question) {
    final decoded = _decodeObject(raw);
    if (decoded == null) return ProReasoningFrame.fallback(question);
    final subQuestions = _stringList(decoded['sub_questions']);
    final criteria = _stringList(decoded['success_criteria']);
    return ProReasoningFrame(
      subQuestions: subQuestions.isEmpty
          ? <String>[question.trim()]
          : subQuestions,
      investigationSteps: _stringList(decoded['investigation_steps']),
      successCriteria: criteria.isEmpty
          ? ProReasoningFrame.fallback(question).successCriteria
          : criteria,
      requiresInvestigation:
          decoded['requires_investigation'] as bool? ?? false,
    );
  }

  String buildInvestigationPrompt({
    required String question,
    required ProReasoningFrame frame,
  }) {
    final steps = frame.investigationSteps.isEmpty
        ? '- Find only evidence needed to answer the question.'
        : frame.investigationSteps.map((step) => '- $step').join('\n');
    return '''
Gather concise, trustworthy evidence for the question below. Use only the
provided read-only tools. Do not mutate files, run shell commands, use SSH, or
perform device actions. Stop when the requested facts are grounded.

Question:
$question

Investigation plan:
$steps
'''
        .trim();
  }

  String buildCandidateSharedPrefix({
    required String question,
    required ProReasoningFrame frame,
    required String evidence,
  }) {
    final subQuestions = frame.subQuestions.map((item) => '- $item').join('\n');
    final criteria = frame.successCriteria.map((item) => '- $item').join('\n');
    final groundedEvidence = evidence.trim().isEmpty
        ? '(No external evidence was collected. Do not invent sources.)'
        : evidence.trim();
    return '''
You are one independent candidate in a high-quality reasoning ensemble. Produce
a complete answer that can later be judged against explicit criteria. Treat the
evidence block as trusted observations, but flag conflicts or missing support.

## User question
$question

## Sub-questions
$subQuestions

## Success criteria
$criteria

## Grounded evidence
$groundedEvidence
'''
        .trimRight();
  }

  String buildCandidatePrompt({
    required String sharedPrefix,
    required String angle,
  }) {
    // Keep the assignment last. On a single llama.cpp slot every candidate can
    // then reuse the byte-identical question/evidence prefix via cache_prompt.
    return '''
$sharedPrefix

## Candidate assignment
$angle

Reason independently, then give the best direct answer. Do not mention the
ensemble or this assignment.
'''
        .trim();
  }

  String buildCritiquePrompt({
    required String question,
    required ProReasoningFrame frame,
    required String evidence,
    required List<ProReasoningCandidate> candidates,
  }) {
    final criteria = frame.successCriteria.map((item) => '- $item').join('\n');
    final renderedCandidates = candidates
        .map((candidate) {
          final thinking = candidate.thinkingObserved
              ? 'thinking observed in the response'
              : candidate.thinkingRequested
              ? 'thinking requested but not observed'
              : 'thinking was not requested for this endpoint';
          return '''
### Candidate ${candidate.index}
Model: ${candidate.model}
Endpoint: ${candidate.endpointLabel}
Reasoning capability: $thinking
Answer:
${candidate.answer}
'''
              .trim();
        })
        .join('\n\n');
    return '''
Act as a rubric judge, not a verifier. Rank the candidate answers against the
criteria and grounded evidence. Give special attention to concrete
contradictions: disagreement is the most useful signal from independent
candidates. Do not penalize a candidate merely because its endpoint could not
enable hidden thinking.

Question:
$question

Criteria:
$criteria

Evidence:
${evidence.trim().isEmpty ? '(none)' : evidence.trim()}

$renderedCandidates

Return one JSON object and no prose:
{
  "winner_index": 0,
  "ranking": [0, 1],
  "contradictions": ["..."],
  "assessment": "..."
}
Use the candidate indices shown above.
'''
        .trim();
  }

  ProReasoningCritique parseCritique(
    String raw,
    List<ProReasoningCandidate> candidates,
  ) {
    final fallback = ProReasoningCritique.fallback(candidates);
    final decoded = _decodeObject(raw);
    if (decoded == null) return fallback;
    final validIndices = candidates.map((candidate) => candidate.index).toSet();
    final winner = _asInt(decoded['winner_index']);
    final ranking = switch (decoded['ranking']) {
      final List<dynamic> values =>
        values
            .map(_asInt)
            .whereType<int>()
            .where(validIndices.contains)
            .toSet()
            .toList(growable: false),
      _ => const <int>[],
    };
    return ProReasoningCritique(
      winnerIndex: winner != null && validIndices.contains(winner)
          ? winner
          : fallback.winnerIndex,
      ranking: ranking.isEmpty ? fallback.ranking : ranking,
      contradictions: _stringList(decoded['contradictions']),
      assessment: switch (decoded['assessment']) {
        final String value when value.trim().isNotEmpty => value.trim(),
        _ => fallback.assessment,
      },
    );
  }

  String buildSynthesisPrompt(ProReasoningSynthesisRequest request) {
    final candidates = request.candidates.isEmpty
        ? '(No candidate survived. Answer the original question directly.)'
        : request.candidates
              .map(
                (candidate) =>
                    '### Candidate ${candidate.index} (${candidate.model})\n'
                    '${candidate.answer}',
              )
              .join('\n\n');
    final contradictions = request.critique.contradictions.isEmpty
        ? '(none identified)'
        : request.critique.contradictions.map((item) => '- $item').join('\n');
    final partialNotice = request.cancelRequested
        ? 'The user stopped the internal run. Synthesize the strongest partial answer now.'
        : request.deadlineHit
        ? 'The internal deadline was reached. Synthesize from the available material now.'
        : 'The internal run completed within budget.';
    return '''
Write the final answer to the original user question. The internal frame,
evidence, candidates, and critique below are hidden working material. Do not
describe the pipeline. Resolve contradictions when the evidence supports a
choice; otherwise state the uncertainty plainly. Use tools only if one final
read-only fact is essential.

$partialNotice

## Original question
${request.question}

## Grounded evidence
${request.evidence.trim().isEmpty ? '(none)' : request.evidence.trim()}

## Candidate answers
$candidates

## Rubric assessment
${request.critique.assessment}

## Candidate contradictions
$contradictions
'''
        .trim();
  }

  Map<String, dynamic>? _decodeObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final candidates = <String>[trimmed];
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(1)?.trim();
    if (fenced != null && fenced.isNotEmpty) candidates.add(fenced);
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      candidates.add(trimmed.substring(start, end + 1));
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  List<String> _stringList(Object? value) => switch (value) {
    final List<dynamic> values =>
      values
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(5)
          .toList(growable: false),
    _ => const <String>[],
  };

  int? _asInt(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };
}
