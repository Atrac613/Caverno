import '../entities/message.dart';

/// Outcome status of a KV-cache warm-up attempt.
enum KvCacheWarmupStatus {
  /// A warm-up request was sent to prime the server-side prefix KV cache.
  warmed,

  /// Warm-up was not attempted (a precondition was not met).
  skipped,

  /// The warm-up request was attempted but the endpoint could not be reached
  /// or rejected it. Best-effort: callers treat this as a soft skip.
  failed,
}

class KvCacheWarmupOutcome {
  const KvCacheWarmupOutcome(this.status, [this.detail]);

  final KvCacheWarmupStatus status;
  final String? detail;
}

/// Sends the warm-up completion. Mirrors the chat datasource's
/// `createChatCompletion`, narrowed to the fields warm-up controls so the
/// service stays trivially testable with a fake sender.
typedef KvCacheWarmupSender =
    Future<void> Function({
      required List<Message> messages,
      required List<Map<String, dynamic>> tools,
      required int maxTokens,
      required double temperature,
    });

/// LL22 KV-cache warm-up: issues one minimal completion so a llama.cpp / LM
/// Studio server computes and caches the KV for the stable prompt prefix
/// (system prompt + tool list). When the morning's first interactive turn sends
/// the same prefix, prefill reuses that cache instead of recomputing it cold.
///
/// The service is pure: it builds the warm-up message list and delegates the
/// network call to an injected [KvCacheWarmupSender], catching errors so an
/// unreachable overnight endpoint is reported rather than thrown. It pairs with
/// the LL6 prefix-stable tool loop, where the leading prefix is held stable; the
/// volatile temporal/memory head is a known limitation that llama.cpp
/// `--cache-reuse` partially recovers (quantified by the LL22 measurement tool).
class KvCacheWarmupService {
  const KvCacheWarmupService({
    this.warmupMaxTokens = 1,
    this.warmupTemperature = 0.0,
  });

  /// Keep generation to a single token: only the prefill (prefix KV) matters.
  final int warmupMaxTokens;

  /// Greedy decode: the generated token is discarded, so sampling is irrelevant.
  final double warmupTemperature;

  static const String _warmupUserContent = 'ready';

  Future<KvCacheWarmupOutcome> warm({
    required String systemPrompt,
    required List<Map<String, dynamic>> tools,
    required KvCacheWarmupSender send,
  }) async {
    final trimmed = systemPrompt.trim();
    if (trimmed.isEmpty) {
      return const KvCacheWarmupOutcome(
        KvCacheWarmupStatus.skipped,
        'empty system prompt',
      );
    }

    // Timestamps are not serialized into the request prompt, so a fixed epoch
    // keeps the warm-up deterministic without affecting the warmed prefix.
    final timestamp = DateTime.fromMillisecondsSinceEpoch(0);
    final messages = [
      Message(
        id: 'warmup-system',
        content: trimmed,
        role: MessageRole.system,
        timestamp: timestamp,
      ),
      Message(
        id: 'warmup-user',
        content: _warmupUserContent,
        role: MessageRole.user,
        timestamp: timestamp,
      ),
    ];

    try {
      await send(
        messages: messages,
        tools: tools,
        maxTokens: warmupMaxTokens,
        temperature: warmupTemperature,
      );
      return KvCacheWarmupOutcome(
        KvCacheWarmupStatus.warmed,
        'primed prefix (${tools.length} tool(s))',
      );
    } catch (error) {
      return KvCacheWarmupOutcome(KvCacheWarmupStatus.failed, error.toString());
    }
  }
}
