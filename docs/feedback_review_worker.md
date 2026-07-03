# Feedback Review Worker MVP

The feedback review MVP keeps public feedback intake separate from local code
execution.

## Flow

1. Caverno sends `/feedback` to the Lambda Function URL.
2. Lambda stores the redacted payload in S3.
3. Lambda sends a small `caverno_feedback_review_job` message to SQS.
4. A local worker long-polls SQS, downloads the payload, classifies it, and
   writes a local job archive under `~/.caverno/feedback_worker/jobs/`.
5. Auto-fix candidates can optionally run Codex in an isolated git worktree.
6. Publishing is disabled unless `--publish` is passed explicitly.

## Deploy

```bash
CAVERNO_FEEDBACK_ALLOW_PUBLIC_FUNCTION_URL=1 tool/deploy_feedback_endpoint.sh
```

The deploy helper creates or updates:

- S3 payload bucket and prefix
- Lambda feedback endpoint
- DynamoDB rate-limit table
- SQS review queue and DLQ
- DynamoDB review status table

Useful overrides:

```bash
CAVERNO_FEEDBACK_REVIEW_QUEUE=caverno-feedback-ingest-review
CAVERNO_FEEDBACK_REVIEW_DLQ=caverno-feedback-ingest-review-dlq
CAVERNO_FEEDBACK_REVIEW_STATUS_TABLE=caverno-feedback-ingest-review-status
CAVERNO_FEEDBACK_REVIEW_REPO_OWNER=Atrac613
CAVERNO_FEEDBACK_REVIEW_REPO_NAME=Caverno
CAVERNO_FEEDBACK_REVIEW_DEFAULT_BRANCH=main
```

## Local Worker

Classification-only run:

```bash
dart run tool/feedback_review_worker.dart \
  --queue-url "$CAVERNO_FEEDBACK_REVIEW_QUEUE_URL" \
  --status-table "$CAVERNO_FEEDBACK_REVIEW_STATUS_TABLE"
```

Prepare a Codex fix without publishing:

```bash
dart run tool/feedback_review_worker.dart \
  --queue-url "$CAVERNO_FEEDBACK_REVIEW_QUEUE_URL" \
  --status-table "$CAVERNO_FEEDBACK_REVIEW_STATUS_TABLE" \
  --repo-root /Users/noguwo/Documents/Workspace/Flutter/caverno \
  --enable-codex
```

Create a draft PR after a green verification run:

```bash
dart run tool/feedback_review_worker.dart \
  --queue-url "$CAVERNO_FEEDBACK_REVIEW_QUEUE_URL" \
  --status-table "$CAVERNO_FEEDBACK_REVIEW_STATUS_TABLE" \
  --repo-root /Users/noguwo/Documents/Workspace/Flutter/caverno \
  --enable-codex \
  --publish
```

`--publish` is intentionally separate from `--enable-codex` so the first worker
rollout can consume queue messages and archive evidence without writing git
history or opening pull requests.
