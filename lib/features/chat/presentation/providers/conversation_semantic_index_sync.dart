import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../data/repositories/semantic_indexing_service.dart';
import '../../domain/entities/conversation.dart';
import 'semantic_search_provider.dart';

/// LL5: keeps the semantic index in sync with a conversation's searchable text.
///
/// Coalesces changed conversations behind one embedding job at a time.
final class ConversationSemanticIndexSync {
  ConversationSemanticIndexSync(this._ref) {
    _ref.onDispose(() {
      _retryTimer?.cancel();
      _active?.cancellation.cancel();
      _pending.clear();
    });
  }

  final Ref _ref;
  final Map<String, String> _lastIndexedSignatures = <String, String>{};
  final Map<String, _IndexJob> _pending = <String, _IndexJob>{};
  final Map<String, int> _failureCounts = <String, int>{};
  final Map<String, DateTime> _retryAfter = <String, DateTime>{};
  SemanticIndexingService? _currentIndexer;
  _IndexJob? _active;
  Future<void>? _activeFuture;
  Timer? _retryTimer;

  /// Null while semantic search is off, and while the provider container is
  /// still being disposed -- neither is an error worth failing a save for.
  SemanticIndexingService? get _indexer {
    try {
      return _ref.read(semanticIndexingServiceProvider);
    } catch (_) {
      return null;
    }
  }

  /// Indexes [conversation] unless semantic search is off, a message is still
  /// streaming, or its text has not changed since the last index.
  ///
  /// Fire-and-forget: indexing failures never block or fail the chat loop.
  void schedule(Conversation conversation) {
    final indexer = _indexer;
    if (!identical(indexer, _currentIndexer)) {
      _currentIndexer = indexer;
      _active?.cancellation.cancel();
      _pending.clear();
      _lastIndexedSignatures.clear();
      _failureCounts.clear();
      _retryAfter.clear();
    }
    if (indexer == null) return;
    if (conversation.messages.any((message) => message.isStreaming)) return;

    final signature = signatureFor(conversation);
    if (_pending[conversation.id]?.signature == signature) return;
    if (_active?.conversation.id == conversation.id &&
        _active?.signature == signature) {
      _pending.remove(conversation.id);
      return;
    }
    if (_lastIndexedSignatures[conversation.id] == signature &&
        _active?.conversation.id != conversation.id &&
        !_pending.containsKey(conversation.id)) {
      return;
    }
    _pending[conversation.id] = _IndexJob(conversation, signature);
    _startNext();
  }

  void _startNext() {
    if (_active != null || _pending.isEmpty) return;
    final indexer = _indexer;
    if (indexer == null) {
      _pending.clear();
      return;
    }
    final now = DateTime.now();
    String? nextId;
    DateTime? earliestRetry;
    for (final id in _pending.keys) {
      final retry = _retryAfter[id];
      if (retry == null || !retry.isAfter(now)) {
        nextId = id;
        break;
      }
      if (earliestRetry == null || retry.isBefore(earliestRetry)) {
        earliestRetry = retry;
      }
    }
    if (nextId == null) {
      _retryTimer?.cancel();
      _retryTimer = Timer(earliestRetry!.difference(now), _startNext);
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    final job = _pending.remove(nextId)!;
    _active = job;
    _activeFuture = _run(job, indexer);
  }

  Future<void> _run(_IndexJob job, SemanticIndexingService indexer) async {
    try {
      final indexed = await indexer.indexConversation(
        job.conversation,
        cancellation: job.cancellation,
      );
      if (job.cancellation.isCancelled) return;
      if (indexed) {
        _failureCounts.remove(job.conversation.id);
        _retryAfter.remove(job.conversation.id);
        if (!_pending.containsKey(job.conversation.id)) {
          _lastIndexedSignatures[job.conversation.id] = job.signature;
        }
      } else {
        _backOff(job.conversation.id);
      }
    } catch (error) {
      if (!job.cancellation.isCancelled) {
        _backOff(job.conversation.id);
        appLog(
          '[ConversationsNotifier] semantic index failed for '
          '${job.conversation.id}: $error',
        );
      }
    } finally {
      _active = null;
      _startNext();
    }
  }

  void _backOff(String id) {
    final failures = (_failureCounts[id] ?? 0) + 1;
    _failureCounts[id] = failures;
    final seconds = (5 * (1 << (failures - 1).clamp(0, 4).toInt()))
        .clamp(5, 60)
        .toInt();
    _retryAfter[id] = DateTime.now().add(Duration(seconds: seconds));
  }

  /// Drops index entries (and the cached signature) for deleted conversations.
  void remove(Iterable<String> ids) {
    final indexer = _indexer;
    for (final id in ids) {
      _lastIndexedSignatures.remove(id);
      _pending.remove(id);
      _failureCounts.remove(id);
      _retryAfter.remove(id);
      final active = _active?.conversation.id == id ? _active : null;
      active?.cancellation.cancel();
      if (indexer == null) continue;
      unawaited(
        (_activeFuture ?? Future<void>.value())
            .then((_) => indexer.deleteConversation(id))
            .catchError((Object error) {
              appLog(
                '[ConversationsNotifier] semantic index delete failed for '
                '$id: $error',
              );
            }),
      );
    }
  }

  /// A process-local fingerprint of the searchable text. Include the content
  /// so equal-length edits still replace stale embeddings.
  String signatureFor(Conversation conversation) {
    return Object.hash(
      conversation.title,
      Object.hashAll(
        conversation.messages.map(
          (message) => Object.hash(message.id, message.content),
        ),
      ),
    ).toString();
  }
}

final class _IndexJob {
  _IndexJob(this.conversation, this.signature);

  final Conversation conversation;
  final String signature;
  final EmbeddingJobCancellation cancellation = EmbeddingJobCancellation();
}
