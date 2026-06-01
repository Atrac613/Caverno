import 'package:caverno/features/chat/presentation/providers/custom_slash_commands_notifier.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command_prompt_template.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CustomSlashCommandsNotifier', () {
    test('persists and reloads custom templates', () async {
      final prefs = await _preferences();
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container
          .read(customSlashCommandsNotifierProvider.notifier)
          .upsert(
            const SlashCommandPromptTemplate(
              id: 'cmd-1',
              name: 'summarize',
              description: 'Summarize a target',
              aliases: ['sum'],
              argumentHint: '<target>',
              template: 'Summarize {input}',
            ),
          );

      expect(
        container.read(customSlashCommandsNotifierProvider).single.name,
        'summarize',
      );
      expect(
        prefs.getString(CustomSlashCommandsNotifier.storageKey),
        contains('summarize'),
      );

      final reloaded = _container(prefs);
      addTearDown(reloaded.dispose);

      final templates = reloaded.read(customSlashCommandsNotifierProvider);
      expect(templates, hasLength(1));
      expect(templates.single.aliases, ['sum']);
      expect(
        templates.single.expand(args: 'chat', commandName: 'sum'),
        'Summarize chat',
      );
    });

    test('rejects invalid names and built-in overrides', () async {
      final prefs = await _preferences();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(
        customSlashCommandsNotifierProvider.notifier,
      );

      await expectLater(
        notifier.upsert(
          const SlashCommandPromptTemplate(
            id: 'invalid',
            name: 'tmp/path',
            description: 'Invalid command',
            template: 'Run {input}',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        notifier.upsert(
          const SlashCommandPromptTemplate(
            id: 'reserved',
            name: 'review',
            description: 'Reserved command',
            template: 'Review {input}',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects duplicate custom names and aliases', () async {
      final prefs = await _preferences();
      final container = _container(prefs);
      addTearDown(container.dispose);
      final notifier = container.read(
        customSlashCommandsNotifierProvider.notifier,
      );

      await notifier.upsert(
        const SlashCommandPromptTemplate(
          id: 'first',
          name: 'summarize',
          description: 'Summarize a target',
          aliases: ['sum'],
          template: 'Summarize {input}',
        ),
      );

      await expectLater(
        notifier.upsert(
          const SlashCommandPromptTemplate(
            id: 'second',
            name: 'brief',
            description: 'Create a brief',
            aliases: ['sum'],
            argumentRequirement: SlashCommandArgumentRequirement.optional,
            template: 'Brief {input}',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('drops argument hints for no-argument commands', () async {
      final prefs = await _preferences();
      final container = _container(prefs);
      addTearDown(container.dispose);

      await container
          .read(customSlashCommandsNotifierProvider.notifier)
          .upsert(
            const SlashCommandPromptTemplate(
              id: 'daily',
              name: 'daily',
              description: 'Create a daily summary',
              argumentHint: '<input>',
              argumentRequirement: SlashCommandArgumentRequirement.none,
              template: 'Create a daily summary.',
            ),
          );

      final template = container
          .read(customSlashCommandsNotifierProvider)
          .single;
      expect(template.argumentHint, isNull);
      expect(template.toDefinition().usage, '/daily');
    });
  });
}

Future<SharedPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}
