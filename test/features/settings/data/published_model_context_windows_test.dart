import 'package:caverno/features/settings/data/published_model_context_windows.dart';
import 'package:caverno/features/settings/domain/entities/model_catalog_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublishedModelContextWindows', () {
    test('resolves the GPT-5.6 family', () {
      expect(PublishedModelContextWindows.lookup('gpt-5.6-luna'), 1050000);
      expect(PublishedModelContextWindows.lookup('gpt-5.6-sol'), 1050000);
      expect(PublishedModelContextWindows.lookup('gpt-5.6-terra'), 1050000);
    });

    test('ignores surrounding whitespace and case', () {
      expect(PublishedModelContextWindows.lookup('  GPT-5.6-Luna '), 1050000);
    });

    test('lets a dated snapshot inherit from its base model', () {
      expect(
        PublishedModelContextWindows.lookup('gpt-5.6-luna-2026-08-01'),
        1050000,
      );
    });

    test('does not extend a listed id to a differently named variant', () {
      // A `-mini` / `-pro` sibling is its own model with its own window; only a
      // dated snapshot may inherit.
      expect(PublishedModelContextWindows.lookup('gpt-5.6-luna-mini'), isNull);
      expect(PublishedModelContextWindows.lookup('gpt-5.6-luna-pro'), isNull);
      expect(
        PublishedModelContextWindows.lookup('gpt-5.6-luna-2026-08'),
        isNull,
      );
    });

    test('returns null for unlisted and empty ids', () {
      expect(PublishedModelContextWindows.lookup('qwen3.6-27b-vision'), isNull);
      expect(PublishedModelContextWindows.lookup(''), isNull);
      expect(PublishedModelContextWindows.lookup('   '), isNull);
    });
  });

  group('PublishedModelContextWindows.fill', () {
    test('fills a silent entry and records the provenance', () {
      // OpenAI's /v1/models carries no context window at all.
      final filled = PublishedModelContextWindows.fill(const [
        ModelCatalogEntry(id: 'gpt-5.6-luna', ownedBy: 'openai'),
      ]);

      expect(filled, [
        const ModelCatalogEntry(
          id: 'gpt-5.6-luna',
          ownedBy: 'openai',
          contextWindowTokens: 1050000,
          contextWindowSource: ModelContextWindowSource.publishedSpec,
        ),
      ]);
    });

    test('keeps an endpoint-reported window over the published spec', () {
      // A gateway serving the same id with a reduced window must win: the table
      // is a fallback, not an override.
      final filled = PublishedModelContextWindows.fill(const [
        ModelCatalogEntry(
          id: 'gpt-5.6-luna',
          ownedBy: 'proxy',
          contextWindowTokens: 32768,
        ),
      ]);

      expect(filled.single.contextWindowTokens, 32768);
      expect(
        filled.single.contextWindowSource,
        ModelContextWindowSource.endpoint,
      );
    });

    test('leaves an unlisted silent model unmeasured', () {
      final filled = PublishedModelContextWindows.fill(const [
        ModelCatalogEntry(id: 'mystery-model'),
      ]);

      expect(filled.single.contextWindowTokens, isNull);
      expect(
        filled.single.contextWindowSource,
        ModelContextWindowSource.endpoint,
      );
    });

    test('passes an empty catalog through', () {
      expect(PublishedModelContextWindows.fill(const []), isEmpty);
    });
  });
}
