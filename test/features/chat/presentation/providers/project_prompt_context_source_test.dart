import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/presentation/providers/project_prompt_context_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared gate for project-scoped prompt blocks, moved out of
/// ChatNotifier: a coding-capable mode with a selected project root.
void main() {
  late ProviderContainer container;
  late ProjectPromptContextSource source;
  final root = Directory.current.path;

  setUp(() {
    container = ProviderContainer();
    source = container.read(projectPromptContextSourceProvider);
  });

  tearDown(() => container.dispose());

  test('general mode gets neither block', () {
    expect(source.repoMap(AssistantMode.general, root, null), isNull);
    expect(
      source.environmentGrounding(AssistantMode.general, root, null),
      isNull,
    );
  });

  test('no selected project gets no environment block', () {
    expect(
      source.environmentGrounding(AssistantMode.coding, null, null),
      isNull,
    );
  });

  test('a coding or plan turn on a locked project gets the KC2 block', () {
    for (final mode in [AssistantMode.coding, AssistantMode.plan]) {
      final block = source.environmentGrounding(mode, root, null);
      expect(block, startsWith('Project toolchain and dependencies'));
      // 1,600 for the versions plus 1,600 for the change digest by default.
      expect(block!.length, lessThanOrEqualTo(3201));
    }
  });

  test('usable context sets the cap, and the builder is shared', () {
    final small = source.environmentGrounding(
      AssistantMode.coding,
      root,
      8192,
    )!;
    final large = source.environmentGrounding(
      AssistantMode.coding,
      root,
      131072,
    )!;
    expect(small.length, lessThanOrEqualTo(400));
    expect(large, isNot(contains('not listed')));
    expect(
      identical(
        container.read(environmentGroundingContextBuilderProvider),
        container.read(environmentGroundingContextBuilderProvider),
      ),
      isTrue,
    );
  });
}
