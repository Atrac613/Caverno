import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../data/datasources/environment_grounding_context_builder.dart';
import '../../domain/services/repo_map_lsp_symbol_cache.dart';
import '../../domain/services/repo_map_precompute_cache.dart';
import 'repo_map_precompute_cache_provider.dart';

/// The project-scoped system-prompt blocks: the LL22 repo map and the KC2
/// environment block.
///
/// The KC2 block is not wired into ChatNotifier's prompt: its 2026-09-24
/// paired re-run was negative (class 4 regressed to 100% stale), so it was
/// withdrawn. [environmentGrounding] stays for measurement and a later
/// re-promotion that clears the same re-run.
///
/// Kept out of ChatNotifier, whose library is at its size ratchet; the
/// notifier resolves the mode, project root, and usable context, and this
/// decides what each block contains. Both share one gate: a coding-capable
/// mode with a selected project. That gate is what the KC2 scope's "explicitly
/// selected coding project" means; no separate prompt data-perimeter policy
/// governs system-prompt blocks.
class ProjectPromptContextSource {
  const ProjectPromptContextSource({
    required this.repoMapCache,
    required this.lspSymbolCache,
    required this.environmentBuilder,
  });

  final RepoMapPrecomputeCache repoMapCache;
  final RepoMapLspSymbolCache lspSymbolCache;
  final EnvironmentGroundingContextBuilder environmentBuilder;

  String? repoMap(
    AssistantMode assistantMode,
    String? projectRoot,
    int? usableContextTokens,
  ) {
    if (assistantMode == AssistantMode.general) return null;
    // LL22: serve from the precompute cache when the project signature is
    // unchanged; otherwise this rebuilds and stores it (a cold first turn).
    return repoMapCache.getOrBuild(
      rootPath: projectRoot,
      usableContextTokens: usableContextTokens,
      lspSymbolEntries: lspSymbolCache.entriesForRoot(projectRoot),
    );
  }

  String? environmentGrounding(
    AssistantMode assistantMode,
    String? projectRoot,
    int? usableContextTokens,
  ) {
    if (assistantMode == AssistantMode.general || projectRoot == null) {
      return null;
    }
    return environmentBuilder.build(
      projectRoot,
      maxChars: EnvironmentGroundingContextBuilder.maxCharsForUsableContext(
        usableContextTokens,
      ),
      digestMaxChars:
          EnvironmentGroundingContextBuilder.digestMaxCharsForUsableContext(
            usableContextTokens,
          ),
    );
  }
}

/// Process-wide KC2 block builder. Kept alive for the app session so its
/// file-fingerprint cache returns identical bytes on every turn in a project
/// until the lockfile, manifest, package config, or SDK version file changes.
final environmentGroundingContextBuilderProvider =
    Provider<EnvironmentGroundingContextBuilder>(
      (_) => EnvironmentGroundingContextBuilder(),
    );

final projectPromptContextSourceProvider = Provider<ProjectPromptContextSource>(
  (ref) => ProjectPromptContextSource(
    repoMapCache: ref.read(repoMapPrecomputeCacheProvider),
    lspSymbolCache: ref.read(repoMapLspSymbolCacheProvider),
    environmentBuilder: ref.read(environmentGroundingContextBuilderProvider),
  ),
);
