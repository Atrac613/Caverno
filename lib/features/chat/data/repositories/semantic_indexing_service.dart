import 'dart:async';
import 'dart:convert';

import '../../domain/entities/conversation.dart';
import '../datasources/embeddings_client.dart';
import 'conversation_chunker.dart';
import 'drift_embedding_store.dart';

/// Cancellation shared by an index job and its current HTTP request.
final class EmbeddingJobCancellation {
  final Completer<void> _completer = Completer<void>();

  Future<void> get signal => _completer.future;
  bool get isCancelled => _completer.isCompleted;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// LL5 indexing: chunks a conversation, embeds the chunks, and stores the
/// vectors for semantic search.
///
/// Degrades gracefully: if embeddings are unavailable (no endpoint, error) the
/// conversation is left un-indexed and `indexConversation` returns false, so
/// lexical FTS keeps working without blocking saves.
class SemanticIndexingService {
  SemanticIndexingService({
    required this.embed,
    required this.store,
    required this.model,
    this.chunker = const ConversationChunker(),
    this.embedWithCancellation,
    this.maxInputsPerRequest = 16,
    this.maxRequestBytes = 16 * 1024,
  }) : assert(maxInputsPerRequest > 0),
       assert(maxRequestBytes > 0);

  static const sourceType = 'conversation';

  final EmbedTexts embed;
  final DriftEmbeddingStore store;
  final String model;
  final ConversationChunker chunker;
  final Future<EmbeddingsResult?> Function(List<String>, Future<void>)?
  embedWithCancellation;
  final int maxInputsPerRequest;
  final int maxRequestBytes;

  /// Returns true when the conversation's index is up to date (indexed or
  /// nothing to index), false when embeddings were unavailable.
  Future<bool> indexConversation(
    Conversation conversation, {
    EmbeddingJobCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) return false;
    final chunks = chunker.chunk(conversation);
    if (chunks.isEmpty) {
      await store.deleteForSource(
        sourceType: sourceType,
        sourceId: conversation.id,
      );
      return true;
    }

    final vectors = <List<double>>[];
    var batch = <String>[];
    String? responseModel;
    int? vectorDimension;

    Future<bool> flush() async {
      if (batch.isEmpty) return true;
      if (cancellation?.isCancelled ?? false) return false;
      final embedded = cancellation != null && embedWithCancellation != null
          ? await embedWithCancellation!(batch, cancellation.signal)
          : await embed(batch);
      if (cancellation?.isCancelled ?? false) return false;
      if (embedded == null || embedded.vectors.length != batch.length) {
        return false;
      }
      final batchDimension = embedded.vectors.first.length;
      if ((responseModel != null && embedded.model != responseModel) ||
          embedded.vectors.any(
            (vector) =>
                batchDimension == 0 ||
                vector.length != batchDimension ||
                (vectorDimension != null && batchDimension != vectorDimension),
          )) {
        return false;
      }
      responseModel ??= embedded.model;
      vectorDimension ??= batchDimension;
      vectors.addAll(embedded.vectors);
      batch = <String>[];
      return true;
    }

    for (final chunk in chunks) {
      final candidate = [...batch, chunk.text];
      if (candidate.length > maxInputsPerRequest ||
          _requestBytes(candidate) > maxRequestBytes) {
        if (!await flush()) return false;
      }
      batch.add(chunk.text);
      if (_requestBytes(batch) > maxRequestBytes) return false;
    }
    if (!await flush()) return false;
    if (cancellation?.isCancelled ?? false) return false;

    await store.replaceForSource(
      sourceType: sourceType,
      sourceId: conversation.id,
      model: model,
      chunks: [
        for (var i = 0; i < chunks.length; i += 1)
          EmbeddingChunk(
            chunkIndex: chunks[i].index,
            snippet: chunks[i].snippet,
            vector: vectors[i],
          ),
      ],
    );
    return true;
  }

  int _requestBytes(List<String> inputs) =>
      utf8.encode(jsonEncode({'model': model, 'input': inputs})).length;

  /// Removes any stored vectors for a deleted conversation.
  Future<void> deleteConversation(String conversationId) {
    return store.deleteForSource(
      sourceType: sourceType,
      sourceId: conversationId,
    );
  }
}
