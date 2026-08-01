import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/data/repositories/key_value_store.dart';
import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _MutableSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(mcpEnabled: false);

  void rebuildToolService() {
    state = state.copyWith(disabledBuiltInTools: const ['read_file']);
  }
}

class _FakeConversationRepository implements ConversationRepositoryApi {
  @override
  List<Conversation> getAll() => const [];

  @override
  Conversation? getById(String id) => null;

  @override
  Future<Conversation?> refresh(String id) async => null;

  @override
  Future<void> save(Conversation conversation) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> deleteAll() async {}

  @override
  Future<List<Conversation>> search(String query) async => const [];
}

class _MapKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  bool get isReady => true;

  @override
  String? get(String key) => _values[key];

  @override
  Future<void> refresh(Iterable<String> keys) async {}

  @override
  Future<void> put(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

void main() {
  test(
    'settings rebuild keeps the exact file rollback checkpoint store',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'mcp_tool_provider_rollback_store_test_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_MutableSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatMemoryRepositoryProvider.overrideWithValue(
            ChatMemoryRepository(_MapKeyValueStore()),
          ),
          skillRepositoryProvider.overrideWithValue(SkillRepository.inMemory()),
        ],
      );
      addTearDown(container.dispose);

      final owner = ChatTurnOwner(
        conversationId: 'provider-rebuild-conversation',
        interactionGeneration: 7,
      );
      final target = File(
        '${tempDir.path}${Platform.pathSeparator}created_after_rebuild.txt',
      );
      final sharedStore = container.read(fileRollbackCheckpointStoreProvider);
      final oldService = container.read(mcpToolServiceProvider)!;

      expect(
        oldService.filesystemToolHandler.checkpointStore,
        same(sharedStore),
      );
      oldService.beginFileTurnCheckpoint(owner, 'turn-before-rebuild');

      (container.read(settingsNotifierProvider.notifier)
              as _MutableSettingsNotifier)
          .rebuildToolService();
      final newService = container.read(mcpToolServiceProvider)!;

      expect(newService, isNot(same(oldService)));
      expect(
        newService.filesystemToolHandler.checkpointStore,
        same(sharedStore),
      );

      final writeResult = await newService.executeFileTool(
        owner: owner,
        name: 'write_file',
        arguments: <String, dynamic>{
          'path': target.path,
          'content': 'created after rebuild\n',
        },
      );
      expect(writeResult.isSuccess, isTrue);
      expect(oldService.endFileTurnCheckpoint(owner), isTrue);

      final preview = await newService.previewFsTurn(owner.conversationId);
      expect(preview, isNotNull);
      expect(preview!.owner, owner);
      expect(preview.turnId, 'turn-before-rebuild');
      expect(preview.paths, [target.absolute.path]);

      final rollback = await newService.rollbackLastFileTurnCheckpoint(
        preview.owner,
        preview.checkpointToken,
      );
      expect(rollback.isSuccess, isTrue);
      expect(target.existsSync(), isFalse);
      expect(await newService.previewFsTurn(owner.conversationId), isNull);
    },
  );
}
