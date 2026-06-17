import '../../domain/entities/conversation.dart';
import '../datasources/embeddings_client.dart';
import 'conversation_chunker.dart';
import 'drift_embedding_store.dart';

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
  });

  static const sourceType = 'conversation';

  final EmbedTexts embed;
  final DriftEmbeddingStore store;
  final String model;
  final ConversationChunker chunker;

  /// Returns true when the conversation's index is up to date (indexed or
  /// nothing to index), false when embeddings were unavailable.
  Future<bool> indexConversation(Conversation conversation) async {
    final chunks = chunker.chunk(conversation);
    if (chunks.isEmpty) {
      await store.deleteForSource(
        sourceType: sourceType,
        sourceId: conversation.id,
      );
      return true;
    }

    final embedded = await embed([for (final chunk in chunks) chunk.text]);
    // Unavailable, or a malformed count mismatch: skip rather than store a
    // misaligned index.
    if (embedded == null || embedded.vectors.length != chunks.length) {
      return false;
    }

    await store.replaceForSource(
      sourceType: sourceType,
      sourceId: conversation.id,
      model: model,
      chunks: [
        for (var i = 0; i < chunks.length; i += 1)
          EmbeddingChunk(
            chunkIndex: chunks[i].index,
            snippet: chunks[i].snippet,
            vector: embedded.vectors[i],
          ),
      ],
    );
    return true;
  }
}
