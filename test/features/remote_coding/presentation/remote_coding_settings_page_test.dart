import 'dart:convert';

import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_settings_page.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();
}

class _TestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

void main() {
  testWidgets('desktop settings copy a redacted P1 support packet', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = Map<String, dynamic>.from(
            call.arguments as Map<dynamic, dynamic>,
          );
          clipboardText = data['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final repository = RemoteCodingRepository(preferences);
    await repository.saveServerSettings(
      RemoteCodingServerSettings(
        enabled: false,
        port: 8767,
        pairedDevices: [
          RemoteCodingPairedDevice(
            id: 'device-1',
            name: 'Phone',
            tokenHash: RemoteCodingSecurity.hashToken('mobile-token'),
            createdAt: DateTime(2026, 5, 26, 12),
            lastSeenAt: DateTime(2026, 5, 26, 12, 30),
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        remoteCodingRepositoryProvider.overrideWithValue(repository),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatNotifierProvider.overrideWith(_TestChatNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RemoteCodingSettingsPage()),
      ),
    );

    await tester.tap(find.text('Copy Support Packet'));
    await tester.pump();

    final packet = jsonDecode(clipboardText!) as Map<String, dynamic>;
    final checklistPatch =
        packet['manualChecklistPatch'] as Map<String, dynamic>;
    final supportPacket =
        checklistPatch['supportPacket'] as Map<String, dynamic>;
    final encoded = jsonEncode(packet);

    expect(packet['schemaName'], 'remote_coding_p1_support_packet');
    expect(packet['side'], 'desktop');
    expect(supportPacket['desktopDiagnosticsCopied'], isTrue);
    expect(supportPacket['mobileDiagnosticsCopied'], isFalse);
    expect(supportPacket['diagnosticsContainNoTokenMaterial'], isTrue);
    expect(supportPacket['supportPacketIdentifiesEndpointAndProtocol'], isTrue);
    expect(encoded, isNot(contains('mobile-token')));
    expect(
      encoded,
      isNot(contains(RemoteCodingSecurity.hashToken('mobile-token'))),
    );
  });
}
