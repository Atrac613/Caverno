import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/conversation.dart';

/// F4 history full-text search UI. Backed by [ConversationRepositoryApi.search]
/// (FTS5 on drift, in-memory fallback on Hive). Returns the selected
/// conversation id via [close].
class ConversationSearchDelegate extends SearchDelegate<String?> {
  ConversationSearchDelegate({required this.search})
    : super(searchFieldLabel: 'drawer.search_hint'.tr());

  final Future<List<Conversation>> Function(String query) search;

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const BackButtonIcon(),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<Conversation>>(
      future: search(trimmed),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? const <Conversation>[];
        if (results.isEmpty) {
          return Center(child: Text('drawer.search_no_results'.tr()));
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final conversation = results[index];
            final snippet = _snippet(conversation);
            return ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(
                _title(conversation),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: snippet == null
                  ? null
                  : Text(snippet, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => close(context, conversation.id),
            );
          },
        );
      },
    );
  }

  String _title(Conversation conversation) {
    final title = conversation.title.trim();
    return title.isEmpty ? 'drawer.search_untitled'.tr() : title;
  }

  String? _snippet(Conversation conversation) {
    for (final message in conversation.messages) {
      final text = message.content.trim();
      if (text.isNotEmpty) {
        return text.replaceAll(RegExp(r'\s+'), ' ');
      }
    }
    return null;
  }
}
