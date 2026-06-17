import '../../domain/entities/conversation.dart';

/// A chunk of conversation text to embed, with a short snippet for display.
class EmbeddingTextChunk {
  const EmbeddingTextChunk({
    required this.index,
    required this.text,
    required this.snippet,
  });

  final int index;

  /// Whitespace-collapsed, length-bounded text sent to the embeddings model.
  final String text;

  /// Short snippet shown in search results.
  final String snippet;
}

/// LL5 chunking: turns a conversation into embeddable text chunks — the title
/// followed by one chunk per non-empty message. Text is whitespace-collapsed
/// and capped so a single long message cannot blow up embedding token cost.
class ConversationChunker {
  const ConversationChunker({
    this.maxCharsPerChunk = 2000,
    this.maxSnippetChars = 160,
  });

  final int maxCharsPerChunk;
  final int maxSnippetChars;

  List<EmbeddingTextChunk> chunk(Conversation conversation) {
    final chunks = <EmbeddingTextChunk>[];
    var index = 0;

    void add(String raw) {
      final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) return;
      final bounded = text.length > maxCharsPerChunk
          ? text.substring(0, maxCharsPerChunk)
          : text;
      final snippet = text.length > maxSnippetChars
          ? '${text.substring(0, maxSnippetChars)}…'
          : text;
      chunks.add(
        EmbeddingTextChunk(index: index++, text: bounded, snippet: snippet),
      );
    }

    add(conversation.title);
    for (final message in conversation.messages) {
      add(message.content);
    }
    return chunks;
  }
}
