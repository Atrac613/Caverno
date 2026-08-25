import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../data/repositories/semantic_indexing_service.dart';
import '../../domain/entities/conversation.dart';
import 'semantic_search_provider.dart';

/// LL5: keeps the semantic index in sync with a conversation's searchable text.
///
/// Owns the per-conversation signature map because deduping is the whole point:
/// saves fire repeatedly during a turn, and embedding each one would spend a
/// `/v1/embeddings` round trip per keystroke-sized change. The service is
/// resolved per call so semantic search staying off costs nothing, and every
/// failure path forgets the signature so the next save retries rather than
/// treating the conversation as indexed.
final class ConversationSemanticIndexSync {
  ConversationSemanticIndexSync(this._ref);

  final Ref _ref;
  final Map<String, String> _lastIndexedSignatures = <String, String>{};

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
  /// Fire-and-forget: indexing failures never block or fail the chat loop, and
  /// a failed turn is re-indexed next time.
  void schedule(Conversation conversation) {
    final indexer = _indexer;
    if (indexer == null) return;
    if (conversation.messages.any((message) => message.isStreaming)) return;

    final signature = signatureFor(conversation);
    if (_lastIndexedSignatures[conversation.id] == signature) return;
    _lastIndexedSignatures[conversation.id] = signature;

    unawaited(
      indexer
          .indexConversation(conversation)
          .then((indexed) {
            // Embeddings were unavailable: forget the signature so the next
            // turn retries instead of treating this state as indexed.
            if (!indexed) {
              _lastIndexedSignatures.remove(conversation.id);
            }
          })
          .catchError((Object error) {
            _lastIndexedSignatures.remove(conversation.id);
            appLog(
              '[ConversationsNotifier] semantic index failed for '
              '${conversation.id}: $error',
            );
          }),
    );
  }

  /// Drops index entries (and the cached signature) for deleted conversations.
  void remove(Iterable<String> ids) {
    final indexer = _indexer;
    for (final id in ids) {
      _lastIndexedSignatures.remove(id);
      if (indexer == null) continue;
      unawaited(
        indexer.deleteConversation(id).catchError((Object error) {
          appLog(
            '[ConversationsNotifier] semantic index delete failed for '
            '$id: $error',
          );
        }),
      );
    }
  }

  /// A cheap fingerprint of the conversation's searchable text: title plus each
  /// message's id and content length. Changes whenever a message is added,
  /// edited, removed, or the title changes, which is exactly when re-indexing
  /// is warranted.
  String signatureFor(Conversation conversation) {
    final buffer = StringBuffer()
      ..write(conversation.title)
      ..writeCharCode(0)
      ..write(conversation.messages.length);
    for (final message in conversation.messages) {
      buffer
        ..writeCharCode(0)
        ..write(message.id)
        ..write(':')
        ..write(message.content.length);
    }
    return buffer.toString();
  }
}
