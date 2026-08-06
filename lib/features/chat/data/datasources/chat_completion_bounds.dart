import 'dart:async';

/// Silence tolerated between streamed chunks. Prompt processing on a local
/// model can run for a minute or more before the first token, so this sits far
/// above any observed gap and only ever catches a dead connection.
const Duration chatStreamIdleTimeout = Duration(minutes: 5);

/// Total budget for a non-streaming completion, which reports no progress
/// until it finishes and so admits no idle measurement.
const Duration chatRequestTimeout = Duration(minutes: 10);

/// Bounds a completion so a wedged connection ends the turn instead of holding
/// it open forever.
///
/// The HTTP client under `openai_dart` has no timeout of its own, so without
/// this a half-open socket is unrecoverable short of an app restart.
Future<T> boundedCompletion<T>(
  Future<T> request,
  String operation, {
  Duration timeout = chatRequestTimeout,
}) {
  return request.timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      '$operation did not respond within ${_describe(timeout)}.',
    ),
  );
}

/// Bounds the gap *between* chunks rather than the total, because a long answer
/// legitimately streams for minutes while silence is the only signal that the
/// connection is wedged rather than slow.
Stream<T> boundedCompletionStream<T>(
  Stream<T> stream,
  String operation, {
  Duration idleTimeout = chatStreamIdleTimeout,
}) {
  return stream.timeout(
    idleTimeout,
    onTimeout: (sink) {
      sink.addError(
        TimeoutException(
          '$operation sent no data for ${_describe(idleTimeout)}.',
        ),
      );
      sink.close();
    },
  );
}

String _describe(Duration duration) {
  return duration.inMinutes >= 1
      ? '${duration.inMinutes} minutes'
      : '${duration.inSeconds}s';
}
