# Feedback Review Worker MVP

The feedback review MVP keeps public feedback intake separate from local code
execution. The SQS queue URL is not a public write endpoint by itself; access to
SQS still requires AWS credentials with queue permissions. The public boundary is
the Lambda Function URL, so production deploys should require the shared
feedback token described below.

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
CAVERNO_FEEDBACK_ALLOW_PUBLIC_FUNCTION_URL=1 \
CAVERNO_FEEDBACK_SHARED_TOKEN="<random-release-token>" \
tool/deploy_feedback_endpoint.sh
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

`CAVERNO_FEEDBACK_SHARED_TOKEN` makes the Lambda require
`x-caverno-feedback-token` on every POST. Deploying a public Function URL without
that token is blocked unless `CAVERNO_FEEDBACK_ALLOW_UNAUTHENTICATED_POST=1` is
set for local smoke testing.

After deployment, configure Caverno Debug settings with both the endpoint URL and
the same feedback auth token.

## Local Worker

Safe dry-run queue inspection:

```bash
dart run tool/feedback_review_worker.dart \
  --queue-url "$CAVERNO_FEEDBACK_REVIEW_QUEUE_URL" \
  --status-table "$CAVERNO_FEEDBACK_REVIEW_STATUS_TABLE" \
  --no-delete
```

`--no-delete` keeps processed SQS messages in the queue so the same payload can
be inspected again before the worker is allowed to consume review jobs. Omit it
when the worker should delete successfully processed messages.

If an auto-fix job is redelivered after a prior Codex or verification failure,
the worker skips another Codex run and marks the job as `needs_manual_review`.
This keeps repeated deterministic failures from spending more local automation
time while still leaving the job archive and status record available for review.

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
