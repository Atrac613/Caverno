import 'dart:async';
import 'dart:convert';
import 'dart:io';

const feedbackReviewWorkerUsage = '''
Usage:
  dart run tool/feedback_review_worker.dart [options]

Options:
  --queue-url <url>          SQS queue URL. Defaults to CAVERNO_FEEDBACK_REVIEW_QUEUE_URL.
  --status-table <name>     Optional DynamoDB status table name.
  --jobs-dir <path>         Local job archive directory.
  --max-messages <count>    Number of SQS messages to process, 1-10. Defaults to 1.
  --wait-seconds <count>    SQS long-poll wait seconds. Defaults to 20.
  --sample-message <path>   Process one local review-job JSON file without AWS polling.
  --no-delete               Do not delete processed SQS messages.
  --enable-codex            Allow auto-fix candidates to run Codex CLI.
  --publish                 Commit, push, and create a draft PR after a green Codex run.
  --repo-root <path>        Repository root used when Codex is enabled.
  --base-branch <name>      Base branch for worktrees and PRs. Defaults to main.
  --worktree-root <path>    Directory for generated git worktrees.
  --verify-command <cmd>    Verification command. Defaults to tool/codex_verify.sh --no-codegen.
  --help                    Show this help.
''';

const _reviewJobSchemaName = 'caverno_feedback_review_job';
const _statusSchemaName = 'caverno_feedback_review_worker_result';
const _defaultVerifyCommand = 'tool/codex_verify.sh --no-codegen';
const _manualReviewAfterReceiveCount = 2;

typedef FeedbackWorkerProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<void> main(List<String> args) async {
  late final FeedbackReviewWorkerOptions options;
  try {
    options = FeedbackReviewWorkerOptions.parse(args);
  } on FeedbackReviewWorkerUsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(feedbackReviewWorkerUsage);
    exitCode = 64;
    return;
  }

  if (options.showHelp) {
    stdout.writeln(feedbackReviewWorkerUsage);
    return;
  }

  try {
    final result = await runFeedbackReviewWorker(options: options);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    if (result.failedCount > 0) {
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
  }
}

Future<FeedbackReviewWorkerResult> runFeedbackReviewWorker({
  required FeedbackReviewWorkerOptions options,
  FeedbackWorkerProcessRunner processRunner = _defaultProcessRunner,
}) {
  return FeedbackReviewWorker(
    options: options,
    processRunner: processRunner,
  ).run();
}

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return Process.run(executable, arguments, workingDirectory: workingDirectory);
}

class FeedbackReviewWorkerUsageException implements Exception {
  const FeedbackReviewWorkerUsageException(this.message);

  final String message;
}

class FeedbackReviewWorkerOptions {
  const FeedbackReviewWorkerOptions({
    required this.queueUrl,
    required this.statusTable,
    required this.jobsDirPath,
    required this.maxMessages,
    required this.waitSeconds,
    required this.sampleMessagePath,
    required this.deleteMessages,
    required this.enableCodex,
    required this.publish,
    required this.repoRootPath,
    required this.baseBranch,
    required this.worktreeRootPath,
    required this.verifyCommand,
    required this.showHelp,
  });

  final String queueUrl;
  final String statusTable;
  final String jobsDirPath;
  final int maxMessages;
  final int waitSeconds;
  final String sampleMessagePath;
  final bool deleteMessages;
  final bool enableCodex;
  final bool publish;
  final String repoRootPath;
  final String baseBranch;
  final String worktreeRootPath;
  final String verifyCommand;
  final bool showHelp;

  factory FeedbackReviewWorkerOptions.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      switch (arg) {
        case '--queue-url':
        case '--status-table':
        case '--jobs-dir':
        case '--max-messages':
        case '--wait-seconds':
        case '--sample-message':
        case '--repo-root':
        case '--base-branch':
        case '--worktree-root':
        case '--verify-command':
          if (index + 1 >= args.length) {
            throw FeedbackReviewWorkerUsageException('$arg requires a value.');
          }
          values[arg] = args[++index];
        case '--no-delete':
        case '--enable-codex':
        case '--publish':
        case '--help':
        case '-h':
          flags.add(arg);
        default:
          throw FeedbackReviewWorkerUsageException('Unknown option: $arg');
      }
    }

    final showHelp = flags.contains('--help') || flags.contains('-h');
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final sampleMessagePath = values['--sample-message']?.trim() ?? '';
    final queueUrl =
        values['--queue-url']?.trim() ??
        Platform.environment['CAVERNO_FEEDBACK_REVIEW_QUEUE_URL']?.trim() ??
        '';
    if (!showHelp && sampleMessagePath.isEmpty && queueUrl.isEmpty) {
      throw const FeedbackReviewWorkerUsageException(
        '--queue-url is required unless --sample-message is provided.',
      );
    }

    final enableCodex = flags.contains('--enable-codex');
    final publish = flags.contains('--publish');
    if (publish && !enableCodex) {
      throw const FeedbackReviewWorkerUsageException(
        '--publish requires --enable-codex.',
      );
    }

    final repoRootPath =
        values['--repo-root']?.trim() ??
        Platform.environment['CAVERNO_FEEDBACK_WORKER_REPO_ROOT']?.trim() ??
        '';
    if (!showHelp && enableCodex && repoRootPath.isEmpty) {
      throw const FeedbackReviewWorkerUsageException(
        '--repo-root is required when --enable-codex is set.',
      );
    }

    return FeedbackReviewWorkerOptions(
      queueUrl: queueUrl,
      statusTable:
          values['--status-table']?.trim() ??
          Platform.environment['CAVERNO_FEEDBACK_REVIEW_STATUS_TABLE']
              ?.trim() ??
          '',
      jobsDirPath:
          values['--jobs-dir']?.trim() ??
          Platform.environment['CAVERNO_FEEDBACK_WORKER_JOBS_DIR']?.trim() ??
          '$home/.caverno/feedback_worker/jobs',
      maxMessages: _parseIntOption(
        values['--max-messages'],
        name: '--max-messages',
        defaultValue: 1,
        min: 1,
        max: 10,
      ),
      waitSeconds: _parseIntOption(
        values['--wait-seconds'],
        name: '--wait-seconds',
        defaultValue: 20,
        min: 0,
        max: 20,
      ),
      sampleMessagePath: sampleMessagePath,
      deleteMessages: !flags.contains('--no-delete'),
      enableCodex: enableCodex,
      publish: publish,
      repoRootPath: repoRootPath,
      baseBranch:
          values['--base-branch']?.trim() ??
          Platform.environment['CAVERNO_FEEDBACK_WORKER_BASE_BRANCH']?.trim() ??
          'main',
      worktreeRootPath:
          values['--worktree-root']?.trim() ??
          Platform.environment['CAVERNO_FEEDBACK_WORKER_WORKTREE_ROOT']
              ?.trim() ??
          '$home/.caverno/feedback_worker/worktrees',
      verifyCommand:
          values['--verify-command']?.trim() ??
          Platform.environment['CAVERNO_FEEDBACK_WORKER_VERIFY_COMMAND']
              ?.trim() ??
          _defaultVerifyCommand,
      showHelp: showHelp,
    );
  }

  static int _parseIntOption(
    String? raw, {
    required String name,
    required int defaultValue,
    required int min,
    required int max,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return defaultValue;
    }
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < min || parsed > max) {
      throw FeedbackReviewWorkerUsageException(
        '$name must be an integer from $min to $max.',
      );
    }
    return parsed;
  }
}

class FeedbackReviewWorker {
  const FeedbackReviewWorker({
    required this.options,
    required this.processRunner,
  });

  final FeedbackReviewWorkerOptions options;
  final FeedbackWorkerProcessRunner processRunner;

  Future<FeedbackReviewWorkerResult> run() async {
    final messages = options.sampleMessagePath.isNotEmpty
        ? [await _loadSampleMessage(options.sampleMessagePath)]
        : await _receiveMessages();
    final results = <FeedbackReviewJobResult>[];
    for (final message in messages) {
      final result = await _processMessage(message);
      results.add(result);
      if (message.receiptHandle.isNotEmpty &&
          options.deleteMessages &&
          result.success) {
        await _deleteMessage(message.receiptHandle);
      }
    }
    return FeedbackReviewWorkerResult(
      receivedCount: messages.length,
      jobs: List.unmodifiable(results),
    );
  }

  Future<_SqsReviewMessage> _loadSampleMessage(String path) async {
    final file = File(path);
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Expected a JSON object in $path.');
    }
    return _SqsReviewMessage.fromJson(decoded, source: path);
  }

  Future<List<_SqsReviewMessage>> _receiveMessages() async {
    final result = await _runAws([
      'sqs',
      'receive-message',
      '--queue-url',
      options.queueUrl,
      '--max-number-of-messages',
      options.maxMessages.toString(),
      '--wait-time-seconds',
      options.waitSeconds.toString(),
      '--message-attribute-names',
      'All',
      '--attribute-names',
      'All',
      '--output',
      'json',
    ]);
    if (result.stdout.toString().trim().isEmpty) {
      return const <_SqsReviewMessage>[];
    }
    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected receive-message JSON object.');
    }
    final rawMessages = decoded['Messages'];
    if (rawMessages is! List) {
      return const <_SqsReviewMessage>[];
    }
    return rawMessages
        .whereType<Map>()
        .map(
          (message) => _SqsReviewMessage.fromJson(
            Map<String, dynamic>.from(message),
            source: options.queueUrl,
          ),
        )
        .toList(growable: false);
  }

  Future<FeedbackReviewJobResult> _processMessage(
    _SqsReviewMessage message,
  ) async {
    late final FeedbackReviewJob job;
    late final Map<String, dynamic> payload;
    late final Directory jobDir;
    try {
      job = FeedbackReviewJob.fromJson(message.body);
      payload = await _loadFeedbackPayload(job);
      jobDir = Directory(
        '${options.jobsDirPath}/${_safeSegment(job.submissionId, 'feedback')}',
      );
      await jobDir.create(recursive: true);
      await File(
        '${jobDir.path}/job.json',
      ).writeAsString(_prettyJson(job.json));
      await File(
        '${jobDir.path}/payload.json',
      ).writeAsString(_prettyJson(payload));
    } catch (error) {
      return FeedbackReviewJobResult.failed(
        submissionId: message.bestEffortSubmissionId,
        status: 'failed_to_load',
        error: error.toString(),
      );
    }

    final classification = FeedbackReviewClassifier.classify(payload);
    final prompt = _buildCodexPrompt(job: job, payload: payload);
    await File(
      '${jobDir.path}/classification.json',
    ).writeAsString(_prettyJson(classification.toJson()));
    await File('${jobDir.path}/codex_prompt.md').writeAsString(prompt);

    var status = classification.statusWhenCodexDisabled;
    var success = true;
    var error = '';
    if (classification.kind ==
            FeedbackReviewClassificationKind.autoFixCandidate &&
        options.enableCodex) {
      if (message.receiveCount >= _manualReviewAfterReceiveCount) {
        status = 'needs_manual_review';
        error =
            'Skipped Codex after prior failed delivery '
            '(ApproximateReceiveCount=${message.receiveCount}).';
        await File('${jobDir.path}/retry_decision.json').writeAsString(
          _prettyJson({
            'decision': 'manual_review',
            'reason': error,
            'receiveCount': message.receiveCount,
          }),
        );
      } else {
        final codexResult = await _runCodexFlow(
          job: job,
          jobDir: jobDir,
          prompt: prompt,
        );
        status = codexResult.status;
        success = codexResult.success;
        error = codexResult.error;
      }
    }

    final result = FeedbackReviewJobResult(
      success: success,
      submissionId: job.submissionId,
      status: status,
      classification: classification.kind.name,
      jobDirPath: jobDir.path,
      error: error,
    );
    await File(
      '${jobDir.path}/result.json',
    ).writeAsString(_prettyJson(result.toJson()));
    await _putStatus(job: job, result: result);
    return result;
  }

  Future<Map<String, dynamic>> _loadFeedbackPayload(
    FeedbackReviewJob job,
  ) async {
    final localPath = job.payload.localPath;
    late final List<int> bytes;
    if (localPath.isNotEmpty) {
      bytes = await File(localPath).readAsBytes();
    } else {
      final bucket = job.payload.bucket;
      final key = job.payload.key;
      if (bucket.isEmpty || key.isEmpty) {
        throw const FormatException(
          'Review job payload bucket and key are required.',
        );
      }
      final result = await _runAws(['s3', 'cp', 's3://$bucket/$key', '-']);
      bytes = utf8.encode(result.stdout.toString());
    }
    final decodedBytes = _maybeDecodeGzip(bytes);
    final decoded = jsonDecode(utf8.decode(decodedBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Feedback payload must be a JSON object.');
    }
    return decoded;
  }

  Future<_CodexFlowResult> _runCodexFlow({
    required FeedbackReviewJob job,
    required Directory jobDir,
    required String prompt,
  }) async {
    final branchName =
        'feature/feedback-${_safeSegment(job.submissionId, 'job')}';
    final worktreePath =
        '${options.worktreeRootPath}/${_safeSegment(job.submissionId, 'job')}';
    await Directory(options.worktreeRootPath).create(recursive: true);
    final worktreeResult = await _runGit([
      'worktree',
      'add',
      '-b',
      branchName,
      worktreePath,
      options.baseBranch,
    ], workingDirectory: options.repoRootPath);
    if (worktreeResult.exitCode != 0) {
      return _CodexFlowResult.failed(
        status: 'worktree_failed',
        error: worktreeResult.stderr.toString(),
      );
    }

    final codexResult = await _runWithStdin(
      'codex',
      ['exec', '--cd', worktreePath, '--sandbox', 'workspace-write', '-'],
      prompt,
      workingDirectory: worktreePath,
    );
    await File(
      '${jobDir.path}/codex_stdout.log',
    ).writeAsString(codexResult.stdout);
    await File(
      '${jobDir.path}/codex_stderr.log',
    ).writeAsString(codexResult.stderr);
    if (codexResult.exitCode != 0) {
      return _CodexFlowResult.failed(
        status: 'codex_failed',
        error: codexResult.stderr,
      );
    }

    final statusResult = await _runGit([
      'status',
      '--short',
    ], workingDirectory: worktreePath);
    await File(
      '${jobDir.path}/git_status.txt',
    ).writeAsString(statusResult.stdout.toString());
    if (statusResult.stdout.toString().trim().isEmpty) {
      return const _CodexFlowResult(success: true, status: 'codex_no_changes');
    }

    final verifyResult = await processRunner('/bin/zsh', [
      '-lc',
      options.verifyCommand,
    ], workingDirectory: worktreePath);
    await File(
      '${jobDir.path}/verify_stdout.log',
    ).writeAsString(verifyResult.stdout.toString());
    await File(
      '${jobDir.path}/verify_stderr.log',
    ).writeAsString(verifyResult.stderr.toString());
    if (verifyResult.exitCode != 0) {
      return _CodexFlowResult.failed(
        status: 'verification_failed',
        error: verifyResult.stderr.toString(),
      );
    }

    if (!options.publish) {
      return const _CodexFlowResult(
        success: true,
        status: 'ready_for_manual_publish',
      );
    }

    final publishResult = await _publishBranch(
      job: job,
      branchName: branchName,
      worktreePath: worktreePath,
    );
    return publishResult;
  }

  Future<_CodexFlowResult> _publishBranch({
    required FeedbackReviewJob job,
    required String branchName,
    required String worktreePath,
  }) async {
    final addResult = await _runGit([
      'add',
      '-A',
    ], workingDirectory: worktreePath);
    if (addResult.exitCode != 0) {
      return _CodexFlowResult.failed(
        status: 'git_add_failed',
        error: addResult.stderr.toString(),
      );
    }
    final diffResult = await _runGit([
      'diff',
      '--cached',
      '--quiet',
    ], workingDirectory: worktreePath);
    if (diffResult.exitCode == 0) {
      return const _CodexFlowResult(success: true, status: 'codex_no_changes');
    }
    final subject = 'fix: Address feedback submission';
    final commitResult = await _runGit([
      'commit',
      '-m',
      subject,
      '-m',
      'Apply the automated fix prepared from feedback submission ${job.submissionId}.',
    ], workingDirectory: worktreePath);
    if (commitResult.exitCode != 0) {
      return _CodexFlowResult.failed(
        status: 'git_commit_failed',
        error: commitResult.stderr.toString(),
      );
    }
    final pushResult = await _runGit([
      'push',
      '-u',
      'origin',
      branchName,
    ], workingDirectory: worktreePath);
    if (pushResult.exitCode != 0) {
      return _CodexFlowResult.failed(
        status: 'git_push_failed',
        error: pushResult.stderr.toString(),
      );
    }
    final prBody = [
      'Automated draft PR for Caverno feedback submission `${job.submissionId}`.',
      '',
      'Verification:',
      '- `${options.verifyCommand}`',
    ].join('\n');
    final prResult = await processRunner('gh', [
      'pr',
      'create',
      '--draft',
      '--base',
      options.baseBranch,
      '--head',
      branchName,
      '--title',
      subject,
      '--body',
      prBody,
    ], workingDirectory: worktreePath);
    if (prResult.exitCode != 0) {
      return _CodexFlowResult.failed(
        status: 'pr_create_failed',
        error: prResult.stderr.toString(),
      );
    }
    return const _CodexFlowResult(success: true, status: 'pr_created');
  }

  Future<void> _putStatus({
    required FeedbackReviewJob job,
    required FeedbackReviewJobResult result,
  }) async {
    if (options.statusTable.isEmpty || options.sampleMessagePath.isNotEmpty) {
      return;
    }
    final item = <String, dynamic>{
      'submissionId': {'S': job.submissionId},
      'status': {'S': result.status},
      'classification': {'S': result.classification},
      'payloadBucket': {'S': job.payload.bucket},
      'payloadKey': {'S': job.payload.key},
      'jobDir': {'S': result.jobDirPath},
      'updatedAt': {'S': DateTime.now().toUtc().toIso8601String()},
    };
    if (result.error.isNotEmpty) {
      item['error'] = {'S': _truncate(result.error, 1024)};
    }
    await _runAws([
      'dynamodb',
      'put-item',
      '--table-name',
      options.statusTable,
      '--item',
      jsonEncode(item),
    ]);
  }

  Future<void> _deleteMessage(String receiptHandle) async {
    await _runAws([
      'sqs',
      'delete-message',
      '--queue-url',
      options.queueUrl,
      '--receipt-handle',
      receiptHandle,
    ]);
  }

  Future<ProcessResult> _runAws(List<String> args) async {
    final result = await processRunner('aws', args);
    if (result.exitCode != 0) {
      throw ProcessException(
        'aws',
        args,
        result.stderr.toString(),
        result.exitCode,
      );
    }
    return result;
  }

  Future<ProcessResult> _runGit(
    List<String> args, {
    required String workingDirectory,
  }) {
    return processRunner('git', args, workingDirectory: workingDirectory);
  }

  Future<_ProcessTextResult> _runWithStdin(
    String executable,
    List<String> args,
    String stdinText, {
    required String workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
    process.stdin.write(stdinText);
    await process.stdin.close();
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    return _ProcessTextResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  }
}

class FeedbackReviewWorkerResult {
  const FeedbackReviewWorkerResult({
    required this.receivedCount,
    required this.jobs,
  });

  final int receivedCount;
  final List<FeedbackReviewJobResult> jobs;

  int get failedCount => jobs.where((job) => !job.success).length;

  Map<String, dynamic> toJson() {
    return {
      'schemaName': _statusSchemaName,
      'receivedCount': receivedCount,
      'failedCount': failedCount,
      'jobs': jobs.map((job) => job.toJson()).toList(),
    };
  }
}

class FeedbackReviewJobResult {
  const FeedbackReviewJobResult({
    required this.success,
    required this.submissionId,
    required this.status,
    this.classification = '',
    this.jobDirPath = '',
    this.error = '',
  });

  const FeedbackReviewJobResult.failed({
    required String submissionId,
    required String status,
    required String error,
  }) : this(
         success: false,
         submissionId: submissionId,
         status: status,
         error: error,
       );

  final bool success;
  final String submissionId;
  final String status;
  final String classification;
  final String jobDirPath;
  final String error;

  Map<String, dynamic> toJson() {
    return {
      'submissionId': submissionId,
      'success': success,
      'status': status,
      if (classification.isNotEmpty) 'classification': classification,
      if (jobDirPath.isNotEmpty) 'jobDir': jobDirPath,
      if (error.isNotEmpty) 'error': error,
    };
  }
}

class FeedbackReviewJob {
  const FeedbackReviewJob({
    required this.json,
    required this.submissionId,
    required this.payload,
    required this.repo,
  });

  final Map<String, dynamic> json;
  final String submissionId;
  final FeedbackReviewPayloadRef payload;
  final FeedbackReviewRepo repo;

  factory FeedbackReviewJob.fromJson(Map<String, dynamic> json) {
    if (json['schemaName'] != _reviewJobSchemaName) {
      throw const FormatException('Unexpected feedback review job schema.');
    }
    final submissionId = _asString(json['submissionId']);
    if (submissionId.isEmpty) {
      throw const FormatException(
        'Feedback review job submissionId is required.',
      );
    }
    return FeedbackReviewJob(
      json: Map<String, dynamic>.from(json),
      submissionId: submissionId,
      payload: FeedbackReviewPayloadRef.fromJson(_asObject(json['payload'])),
      repo: FeedbackReviewRepo.fromJson(_asObject(json['repo'])),
    );
  }
}

class FeedbackReviewPayloadRef {
  const FeedbackReviewPayloadRef({
    required this.bucket,
    required this.key,
    required this.localPath,
  });

  final String bucket;
  final String key;
  final String localPath;

  factory FeedbackReviewPayloadRef.fromJson(Map<String, dynamic> json) {
    return FeedbackReviewPayloadRef(
      bucket: _asString(json['bucket']),
      key: _asString(json['key']),
      localPath: _asString(json['localPath']),
    );
  }
}

class FeedbackReviewRepo {
  const FeedbackReviewRepo({
    required this.owner,
    required this.name,
    required this.defaultBranch,
  });

  final String owner;
  final String name;
  final String defaultBranch;

  factory FeedbackReviewRepo.fromJson(Map<String, dynamic> json) {
    return FeedbackReviewRepo(
      owner: _asString(json['owner']),
      name: _asString(json['name']),
      defaultBranch: _asString(json['defaultBranch']).isEmpty
          ? 'main'
          : _asString(json['defaultBranch']),
    );
  }
}

class FeedbackReviewClassifier {
  static FeedbackReviewClassification classify(Map<String, dynamic> payload) {
    final feedbackText = extractFeedbackText(payload);
    final normalized = feedbackText.toLowerCase();
    final hasActionSignal = const [
      'bug',
      'error',
      'failed',
      'failure',
      'crash',
      'ignored',
      'broken',
      'regression',
      'fix',
      'incorrect',
      'wrong',
      'exception',
      'stack trace',
      'does not work',
    ].any(normalized.contains);
    final hasDocumentationSignal = const [
      'document',
      'docs',
      'readme',
      'explain',
      'unclear',
    ].any(normalized.contains);
    final hasPositiveOnlySignal = const [
      'thanks',
      'thank you',
      'great',
      'works well',
      'looks good',
    ].any(normalized.contains);

    if (feedbackText.trim().isEmpty) {
      return const FeedbackReviewClassification(
        kind: FeedbackReviewClassificationKind.needsManualReview,
        reason: 'Feedback text is empty.',
      );
    }
    if (hasActionSignal) {
      return const FeedbackReviewClassification(
        kind: FeedbackReviewClassificationKind.autoFixCandidate,
        reason: 'Feedback contains a likely fixable failure signal.',
      );
    }
    if (hasDocumentationSignal) {
      return const FeedbackReviewClassification(
        kind: FeedbackReviewClassificationKind.needsManualReview,
        reason: 'Feedback appears to request documentation or explanation.',
      );
    }
    if (hasPositiveOnlySignal) {
      return const FeedbackReviewClassification(
        kind: FeedbackReviewClassificationKind.noAction,
        reason: 'Feedback does not request a change.',
      );
    }
    return const FeedbackReviewClassification(
      kind: FeedbackReviewClassificationKind.needsManualReview,
      reason: 'Feedback needs human triage before automation.',
    );
  }

  static String extractFeedbackText(Map<String, dynamic> payload) {
    final feedback = payload['feedback'];
    if (feedback is String) {
      return feedback.trim();
    }
    if (feedback is Map) {
      return _asString(feedback['text']).trim();
    }
    return '';
  }
}

enum FeedbackReviewClassificationKind {
  noAction,
  needsManualReview,
  autoFixCandidate,
}

class FeedbackReviewClassification {
  const FeedbackReviewClassification({
    required this.kind,
    required this.reason,
  });

  final FeedbackReviewClassificationKind kind;
  final String reason;

  String get statusWhenCodexDisabled {
    switch (kind) {
      case FeedbackReviewClassificationKind.noAction:
        return 'no_action';
      case FeedbackReviewClassificationKind.needsManualReview:
        return 'needs_manual_review';
      case FeedbackReviewClassificationKind.autoFixCandidate:
        return 'auto_fix_pending';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'classification': kind.name,
      'statusWhenCodexDisabled': statusWhenCodexDisabled,
      'reason': reason,
    };
  }
}

class _SqsReviewMessage {
  const _SqsReviewMessage({
    required this.body,
    required this.receiptHandle,
    required this.source,
    required this.receiveCount,
  });

  final Map<String, dynamic> body;
  final String receiptHandle;
  final String source;
  final int receiveCount;

  String get bestEffortSubmissionId => _asString(body['submissionId']);

  factory _SqsReviewMessage.fromJson(
    Map<String, dynamic> json, {
    required String source,
  }) {
    final rawBody = json['Body'] ?? json['body'];
    final receiptHandle = _asString(
      json['ReceiptHandle'] ?? json['receiptHandle'],
    );
    final receiveCount = _parseReceiveCount(json);
    if (rawBody is String && rawBody.trim().isNotEmpty) {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('SQS message body must be a JSON object.');
      }
      return _SqsReviewMessage(
        body: decoded,
        receiptHandle: receiptHandle,
        source: source,
        receiveCount: receiveCount,
      );
    }
    return _SqsReviewMessage(
      body: Map<String, dynamic>.from(json),
      receiptHandle: receiptHandle,
      source: source,
      receiveCount: receiveCount,
    );
  }

  static int _parseReceiveCount(Map<String, dynamic> json) {
    final attributes = json['Attributes'] ?? json['attributes'];
    if (attributes is Map) {
      final value = attributes['ApproximateReceiveCount'];
      final parsed = int.tryParse(_asString(value));
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return 1;
  }
}

class _CodexFlowResult {
  const _CodexFlowResult({
    required this.success,
    required this.status,
    this.error = '',
  });

  const _CodexFlowResult.failed({required String status, required String error})
    : this(success: false, status: status, error: error);

  final bool success;
  final String status;
  final String error;
}

class _ProcessTextResult {
  const _ProcessTextResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

String _buildCodexPrompt({
  required FeedbackReviewJob job,
  required Map<String, dynamic> payload,
}) {
  final feedbackText = FeedbackReviewClassifier.extractFeedbackText(payload);
  final context = _asObject(payload['context']);
  final conversation = _asObject(payload['conversation']);
  final sessionLog = _asObject(payload['sessionLog']);
  final sessionLogContent = _asString(sessionLog['content']);
  return [
    'You are fixing a Caverno feedback submission in an isolated worktree.',
    '',
    'Rules:',
    '- Keep the change tightly scoped to the feedback.',
    '- Follow AGENTS.md and repository conventions.',
    '- Do not commit, push, or create a pull request; the worker owns publishing.',
    '- Run relevant focused checks when possible and report what ran.',
    '',
    'Submission id: ${job.submissionId}',
    'Repository: ${job.repo.owner}/${job.repo.name}',
    'Base branch: ${job.repo.defaultBranch}',
    '',
    'Feedback:',
    feedbackText.isEmpty ? '(empty)' : feedbackText,
    '',
    'Conversation context:',
    _truncate(_prettyJson(context), 6000),
    '',
    'Conversation summary:',
    _truncate(_prettyJson(conversation), 4000),
    '',
    'Session log tail:',
    _tail(sessionLogContent, maxChars: 20000),
  ].join('\n');
}

List<int> _maybeDecodeGzip(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    return gzip.decode(bytes);
  }
  return bytes;
}

Map<String, dynamic> _asObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

String _asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  return value.toString().trim();
}

String _safeSegment(String value, String fallback) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

String _prettyJson(Object value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) {
    return value;
  }
  return '${value.substring(0, maxChars)}\n[truncated]';
}

String _tail(String value, {required int maxChars}) {
  if (value.length <= maxChars) {
    return value;
  }
  return '[truncated]\n${value.substring(value.length - maxChars)}';
}
