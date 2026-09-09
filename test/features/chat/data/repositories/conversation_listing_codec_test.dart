import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_listing_codec.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

void main() {
  const codec = ConversationListingCodec();

  test('keeps routing fields and drops message bodies', () {
    final payload = jsonEncode(
      Conversation(
        id: 'c1',
        title: 'Parser work',
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        messages: [
          Message(
            id: 'm1',
            content: 'huge-tool-result-body',
            role: MessageRole.user,
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(10),
      ).toJson(),
    );

    final listing = codec.decodeFromFullPayload(payload);

    expect(listing, isNotNull);
    expect(listing!.id, 'c1');
    expect(listing.title, 'Parser work');
    expect(listing.projectId, 'project-1');
    expect(listing.messages, hasLength(1));
    expect(listing.messages.single.id, ConversationListingCodec.stubMessageId);
    expect(listing.messages.single.content, isEmpty);
    expect(
      jsonEncode(listing.toJson()),
      isNot(contains('huge-tool-result-body')),
    );
  });

  test('leaves genuinely empty conversations empty', () {
    final payload = jsonEncode(
      Conversation(
        id: 'empty',
        title: 'New conversation',
        messages: const [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(10),
      ).toJson(),
    );

    final listing = codec.decodeFromFullPayload(payload);

    expect(listing, isNotNull);
    expect(listing!.messages, isEmpty);
    expect(ConversationListingCodec.isListingStub(listing.messages), isFalse);
  });

  test('identifies the listing placeholder', () {
    expect(ConversationListingCodec.isListingStub(const []), isFalse);
    expect(
      ConversationListingCodec.isListingStub([
        Message(
          id: ConversationListingCodec.stubMessageId,
          content: '',
          role: MessageRole.user,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ]),
      isTrue,
    );
  });
}
