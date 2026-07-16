import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/semantic_search_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

/// Minimal repository so the search service's lexical fallback can resolve
/// without a Hive box.
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

Future<ProviderContainer> _container(AppSettings settings) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await SettingsRepository(prefs).save(settings);
  final db = AppDatabase.memory();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return container;
}

void main() {
  // Tests intentionally open several in-memory databases.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'builds semantic services when enabled with an embeddings model',
    () async {
      final container = await _container(
        AppSettings.defaults().copyWith(
          enableSemanticSearch: true,
          embeddingsModel: 'text-embed',
        ),
      );

      expect(container.read(embeddingsClientProvider), isNotNull);
      expect(container.read(driftEmbeddingStoreProvider), isNotNull);
      expect(container.read(semanticIndexingServiceProvider), isNotNull);
      expect(container.read(semanticSearchServiceProvider), isNotNull);
    },
  );

  test('semantic services are null when disabled or missing a model', () async {
    final disabled = await _container(
      AppSettings.defaults().copyWith(
        enableSemanticSearch: false,
        embeddingsModel: 'text-embed',
      ),
    );
    expect(disabled.read(embeddingsClientProvider), isNull);
    expect(disabled.read(semanticSearchServiceProvider), isNull);

    final noModel = await _container(
      AppSettings.defaults().copyWith(
        enableSemanticSearch: true,
        embeddingsModel: '',
      ),
    );
    expect(noModel.read(embeddingsClientProvider), isNull);
    expect(noModel.read(semanticSearchServiceProvider), isNull);
  });

  test('vector store and services are null without a database', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SettingsRepository(prefs).save(
      AppSettings.defaults().copyWith(
        enableSemanticSearch: true,
        embeddingsModel: 'text-embed',
      ),
    );
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // appDatabaseProvider defaults to null (Hive fallback) -> store/services off.
    expect(container.read(driftEmbeddingStoreProvider), isNull);
    expect(container.read(semanticSearchServiceProvider), isNull);
    expect(container.read(semanticIndexingServiceProvider), isNull);
  });
}
