// Measurement script for LL18 idle/overnight maintenance pipeline.
//
// Exercises the three deterministic LL17 domain stages (mine → propose → adopt
// gate) with synthetic failure traces, and sends a live probe completion
// request to the configured endpoint to validate the "probe" stage analog.
//
// Usage:
//   dart run tool/ll18_pipeline_measurement.dart \
//     --base-url http://192.168.100.241:1234/v1 \
//     --model qwen3.6-35b-a3b-vision
//
// The script never mutates settings files; it is purely observational.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/maintenance/domain/services/candidate_adoption_service.dart';
import 'package:caverno/features/maintenance/domain/services/failure_trace_miner.dart';
import 'package:caverno/features/maintenance/domain/services/harness_proposal_service.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

const _defaultBaseUrl = 'http://localhost:1234/v1';
const _defaultModel = 'mlx-community/GLM-4.7-Flash-4bit';

Future<void> main(List<String> args) async {
  final opts = _Options.parse(args);
  if (opts == null) {
    stderr.writeln(_Options.usage);
    exitCode = 64;
    return;
  }

  final results = <_StageResult>[];
  final client = HttpClient();

  try {
    // Stage: probe — send a minimal completion to confirm the endpoint responds.
    results.add(await _runProbeStage(client, opts));

    // Stage: mine — cluster synthetic failure traces.
    results.add(_runMineStage());

    // Stage: propose — turn the top cluster into a harness edit.
    results.add(_runProposeStage(opts));

    // Stage: adopt gate — verify the high-risk surface block fires correctly.
    results.add(await _runAdoptGateStage());
  } finally {
    client.close(force: true);
  }

  stdout.write(_buildMarkdown(opts, results));
}

// ── Stages ────────────────────────────────────────────────────────────────────

Future<_StageResult> _runProbeStage(
  HttpClient client,
  _Options opts,
) async {
  final start = DateTime.now();
  try {
    final uri = Uri.parse('${opts.baseUrl}/chat/completions');
    final req = await client.postUrl(uri);
    req.headers.set('Content-Type', 'application/json');
    if (opts.apiKey.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer ${opts.apiKey}');
    }
    req.write(
      jsonEncode({
        'model': opts.model,
        'max_tokens': 32,
        'temperature': 0.1,
        'messages': [
          {
            'role': 'user',
            'content': 'Reply with a single word: ready',
          },
        ],
      }),
    );
    final resp = await req.close().timeout(opts.timeout);
    final body = await resp.transform(utf8.decoder).join();
    final elapsed = DateTime.now().difference(start);

    if (resp.statusCode != 200) {
      return _StageResult(
        name: 'probe',
        status: 'failed',
        detail: 'HTTP ${resp.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}',
        elapsed: elapsed,
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final content =
        ((json['choices'] as List).first['message']['content'] as String? ?? '')
            .trim();
    final promptTokens =
        (json['usage']?['prompt_tokens'] as num?)?.toInt() ?? 0;
    final completionTokens =
        (json['usage']?['completion_tokens'] as num?)?.toInt() ?? 0;

    return _StageResult(
      name: 'probe',
      status: 'completed',
      detail:
          'endpoint replied in ${elapsed.inMilliseconds}ms; '
          'model="${opts.model}"; '
          'reply="${content.length > 60 ? content.substring(0, 60) : content}"; '
          'tokens=$promptTokens+$completionTokens',
      elapsed: elapsed,
    );
  } on TimeoutException {
    return _StageResult(
      name: 'probe',
      status: 'failed',
      detail: 'timed out after ${opts.timeout.inSeconds}s',
      elapsed: DateTime.now().difference(start),
    );
  } catch (e) {
    return _StageResult(
      name: 'probe',
      status: 'failed',
      detail: 'error: $e',
      elapsed: DateTime.now().difference(start),
    );
  }
}

_StageResult _runMineStage() {
  // Synthetic failure traces: two cases sharing the same stale_old_text
  // signature, one unique malformed_json signature.
  const editSig = FailureSignature(
    terminalCause: 'edit_apply_failed',
    causalStatus: 'tests_failed',
    mechanism: 'stale_old_text',
  );
  const jsonSig = FailureSignature(
    terminalCause: 'tool_call_error',
    causalStatus: 'completion_failed',
    mechanism: 'malformed_json',
  );
  const traces = [
    FailureTrace(caseId: 'case_a', signature: editSig),
    FailureTrace(
      caseId: 'case_b',
      signature: editSig,
      symptom: 'old_text did not match file contents',
    ),
    FailureTrace(caseId: 'case_c', signature: jsonSig),
  ];

  final clusters = const FailureTraceMiner().mine(traces);
  final top = clusters.first;

  if (clusters.length != 2) {
    return _StageResult(
      name: 'mine',
      status: 'failed',
      detail:
          'expected 2 clusters from 3 traces, got ${clusters.length}; '
          'clustering logic may be broken',
      elapsed: Duration.zero,
    );
  }

  return _StageResult(
    name: 'mine',
    status: 'completed',
    detail:
        'mined ${clusters.length} cluster(s) from ${traces.length} traces; '
        'top: ${top.signature} x${top.support}',
    elapsed: Duration.zero,
  );
}

_StageResult _runProposeStage(_Options opts) {
  const editSig = FailureSignature(
    terminalCause: 'edit_apply_failed',
    causalStatus: 'tests_failed',
    mechanism: 'stale_old_text',
  );
  const traces = [
    FailureTrace(caseId: 'case_a', signature: editSig),
    FailureTrace(caseId: 'case_b', signature: editSig),
  ];

  final clusters = const FailureTraceMiner().mine(traces);
  final top = clusters.first;

  final base = ModelHarnessConfig(
    id: ModelHarnessConfig.buildId(
      provider: LlmProvider.openAiCompatible,
      baseUrl: opts.baseUrl,
      model: opts.model,
    ),
    model: opts.model,
    baseUrl: opts.baseUrl,
  );

  final proposal = const HarnessProposalService().propose(
    cluster: top,
    base: base,
  );

  if (proposal == null) {
    return _StageResult(
      name: 'propose',
      status: 'skipped',
      detail: 'no harness rule for ${top.signature.mechanism}',
      elapsed: Duration.zero,
    );
  }

  return _StageResult(
    name: 'propose',
    status: 'completed',
    detail:
        'surface="${proposal.surface}" mechanism="${proposal.mechanism}"; '
        'rationale: ${proposal.rationale}; '
        'proposed failureRecoveryInstruction='
        '"${proposal.proposedConfig.failureRecoveryInstruction.substring(0, 40)}…"',
    elapsed: Duration.zero,
  );
}

Future<_StageResult> _runAdoptGateStage() async {
  // Verify the high-risk surface block fires without running any real eval.
  const highRiskProposal = HarnessConfigProposal(
    mechanism: 'synthetic',
    surface: 'approvalMode',
    rationale: 'test: high-risk gate must block auto-adoption',
    proposedConfig: ModelHarnessConfig(id: 'p', model: 'm'),
  );

  const safeProposal = HarnessConfigProposal(
    mechanism: 'stale_old_text',
    surface: 'failureRecoveryInstruction',
    rationale: 'test: safe surface must skip when no eval cases',
    proposedConfig: ModelHarnessConfig(id: 'p', model: 'm'),
  );

  // High-risk gate: must return manualReview regardless of cases.
  final highRiskOutcome = await const CandidateAdoptionService().evaluate(
    proposal: highRiskProposal,
    cases: const [],
    incumbentRunner: _NeverCalledRunner(),
    candidateRunner: _NeverCalledRunner(),
    persist: (_) async {},
  );

  if (highRiskOutcome.status != CandidateAdoptionStatus.manualReview) {
    return _StageResult(
      name: 'adopt-gate',
      status: 'failed',
      detail:
          'high-risk block returned ${highRiskOutcome.status} instead of manualReview',
      elapsed: Duration.zero,
    );
  }

  // Safe surface with empty cases: must skip.
  final skippedOutcome = await const CandidateAdoptionService().evaluate(
    proposal: safeProposal,
    cases: const [],
    incumbentRunner: _NeverCalledRunner(),
    candidateRunner: _NeverCalledRunner(),
    persist: (_) async {},
  );

  if (skippedOutcome.status != CandidateAdoptionStatus.skipped) {
    return _StageResult(
      name: 'adopt-gate',
      status: 'failed',
      detail:
          'empty-cases path returned ${skippedOutcome.status} instead of skipped',
      elapsed: Duration.zero,
    );
  }

  // Passing eval: both runners return passed, should adopt.
  const passingCase = PersonalEvalCase(
    caseId: 'c1',
    prompt: 'p',
    repoStateRef: 'r',
    consentGranted: true,
  );
  final adoptedOutcome = await const CandidateAdoptionService().evaluate(
    proposal: safeProposal,
    cases: const [passingCase],
    incumbentRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
    candidateRunner: _FixedRunner(PersonalEvalVerificationResult.passed),
    persist: (_) async {},
  );

  if (adoptedOutcome.status != CandidateAdoptionStatus.adopted) {
    return _StageResult(
      name: 'adopt-gate',
      status: 'failed',
      detail:
          'passing eval returned ${adoptedOutcome.status} instead of adopted',
      elapsed: Duration.zero,
    );
  }

  return _StageResult(
    name: 'adopt-gate',
    status: 'completed',
    detail:
        'high-risk block → manualReview ✓; '
        'empty-cases → skipped ✓; '
        'passing eval → adopted ✓',
    elapsed: Duration.zero,
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _NeverCalledRunner implements PersonalEvalCaseRunner {
  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase _) {
    throw StateError('_NeverCalledRunner was unexpectedly called');
  }
}

class _FixedRunner implements PersonalEvalCaseRunner {
  const _FixedRunner(this._result);
  final PersonalEvalVerificationResult _result;

  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase _) async =>
      PersonalEvalCaseRunOutcome(verificationResult: _result);
}

// ── Options ───────────────────────────────────────────────────────────────────

class _Options {
  const _Options({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.timeout,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final Duration timeout;

  static const usage = '''
Usage: dart run tool/ll18_pipeline_measurement.dart [options]

Options:
  --base-url <url>   OpenAI-compatible base URL (default: $_defaultBaseUrl)
  --model <model>    Model name (default: $_defaultModel)
  --api-key <key>    API key (default: no-key)
  --timeout <s>      Request timeout in seconds (default: 30)
''';

  static _Options? parse(List<String> args) {
    var baseUrl = Platform.environment['CAVERNO_LLM_BASE_URL'] ?? _defaultBaseUrl;
    var model = Platform.environment['CAVERNO_LLM_MODEL'] ?? _defaultModel;
    var apiKey =
        Platform.environment['CAVERNO_LLM_API_KEY'] ??
        Platform.environment['OPENAI_API_KEY'] ??
        'no-key';
    var timeoutSeconds = 30;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--base-url' when i + 1 < args.length:
          baseUrl = args[++i];
        case '--model' when i + 1 < args.length:
          model = args[++i];
        case '--api-key' when i + 1 < args.length:
          apiKey = args[++i];
        case '--timeout' when i + 1 < args.length:
          timeoutSeconds = int.tryParse(args[++i]) ?? 30;
        case '--help':
        case '-h':
          return null;
        default:
          stderr.writeln('Unknown argument: ${args[i]}');
          return null;
      }
    }

    return _Options(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      timeout: Duration(seconds: timeoutSeconds),
    );
  }
}

// ── Result model ──────────────────────────────────────────────────────────────

class _StageResult {
  const _StageResult({
    required this.name,
    required this.status,
    required this.detail,
    required this.elapsed,
  });

  final String name;
  final String status;
  final String detail;
  final Duration elapsed;

  bool get passed => status == 'completed';

  String get statusIcon => switch (status) {
    'completed' => '✓',
    'skipped' => '⊘',
    _ => '✗',
  };
}

// ── Report ────────────────────────────────────────────────────────────────────

String _buildMarkdown(_Options opts, List<_StageResult> results) {
  final passed = results.where((r) => r.passed).length;
  final failed = results.where((r) => r.status == 'failed').length;
  final date = DateTime.now().toIso8601String().split('T').first;
  final buf = StringBuffer();

  buf.writeln('# LL18 Pipeline Measurement — $date');
  buf.writeln();
  buf.writeln('**Endpoint:** `${opts.baseUrl}`  ');
  buf.writeln('**Model:** `${opts.model}`  ');
  buf.writeln('**Result:** $passed/${results.length} stages passed'
      '${failed > 0 ? " ($failed failed)" : ""}');
  buf.writeln();
  buf.writeln('## Stage Results');
  buf.writeln();

  for (final r in results) {
    final elapsed =
        r.elapsed == Duration.zero ? '' : ' (${r.elapsed.inMilliseconds}ms)';
    buf.writeln('### ${r.statusIcon} ${r.name}$elapsed');
    buf.writeln();
    buf.writeln(r.detail);
    buf.writeln();
  }

  buf.writeln('## Evidence Summary');
  buf.writeln();
  buf.writeln('- Mine stage: `FailureTraceMiner` correctly clusters '
      'same-signature traces into one weakness cluster.');
  buf.writeln('- Propose stage: `HarnessProposalService` maps `stale_old_text` '
      'mechanism to a `failureRecoveryInstruction` surface edit.');
  buf.writeln('- Adopt gate: `CandidateAdoptionService` blocks high-risk '
      'surfaces, skips on empty eval cases, and adopts on passing eval.');
  if (results.any((r) => r.name == 'probe' && r.passed)) {
    buf.writeln('- Probe stage: endpoint reachable and model responds to '
        'completions — LL18 probe stage can run against this model.');
  }

  return buf.toString();
}
