import 'dart:async';

import 'package:caverno/features/chat/data/datasources/save_skill_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/save_skill_tool_contract.dart';
import 'package:caverno/features/chat/presentation/providers/save_skill_notifier_runtime_store.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('success settlement waits for in-flight compensation', () async {
    final repository = _DelayedSkillRepository();
    final container = ProviderContainer(
      overrides: [skillRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(skillsNotifierProvider);
    final notifier = container.read(skillsNotifierProvider.notifier);
    final original = await notifier.upsertMarkdown(
      markdown: '# Race Skill\n\nBase body',
    );
    final store = SaveSkillNotifierRuntimeStore(
      notifier: notifier,
      isOwnerCurrent: (_) => true,
    );
    final runtime = SaveSkillRuntimeInput(
      owner: ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 7,
      ),
      toolCall: ToolCallInfo(
        id: 'save-race',
        name: canonicalSaveSkillToolName,
        arguments: const {'name': 'Race Skill', 'content': '# Runtime body'},
      ),
    ).identity;
    final snapshot = store.captureSnapshot(runtime);
    final write = await store.write(
      SaveSkillRuntimeWriteRequest(
        catalog: SaveSkillCatalogIdentity(
          runtime: runtime,
          catalogDigest: saveSkillCatalogDigest(snapshot.skills!),
        ),
        request: SkillStoreWriteRequest(
          existingId: original.id,
          markdown: '# Race Skill\n\nRuntime body',
        ),
      ),
    );
    final successIdentity = SaveSkillSuccessIdentity(
      mutation: write.identity,
      compensationToken: write.compensationToken!,
      savedSkillDigest: saveSkillDigest(write.skill!),
    );
    repository.delayNextSave();

    final compensation = store.compensate(
      SaveSkillCompensationRequest(
        identity: write.identity,
        compensationToken: write.compensationToken!,
      ),
    );
    await repository.saveStarted.future;
    var settlementCompleted = false;
    final settlement = store.recordSuccess(successIdentity).then((value) {
      settlementCompleted = true;
      return value;
    });

    await Future<void>.delayed(Duration.zero);
    expect(settlementCompleted, isFalse);
    repository.releaseSave();

    expect(
      (await compensation).disposition,
      SaveSkillCompensationDisposition.compensated,
    );
    expect(
      (await settlement).disposition,
      SaveSkillSuccessDisposition.effectUncertain,
    );
    expect(repository.getById(original.id), original);
    expect(notifier.pendingMutationReceiptCount, 0);
  });

  test('owner-check failure during final settlement is compensated', () async {
    final repository = SkillRepository.inMemory();
    final container = ProviderContainer(
      overrides: [skillRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(skillsNotifierProvider);
    final notifier = container.read(skillsNotifierProvider.notifier);
    var failOwnerCheck = false;
    final store = SaveSkillNotifierRuntimeStore(
      notifier: notifier,
      isOwnerCurrent: (_) {
        if (failOwnerCheck) throw StateError('owner lookup failed');
        return true;
      },
    );
    final runtime = SaveSkillToolRuntimeAdapter(
      captureSnapshot: store.captureSnapshot,
      requestFreshManualApproval: (request) async =>
          SaveSkillApprovalAcknowledgement(
            identity: request.identity,
            disposition: SaveSkillApprovalDisposition.approved,
          ),
      acknowledgeOwner: (identity) => SaveSkillOwnerAcknowledgement(
        identity: identity,
        disposition: SaveSkillOwnerDisposition.current,
      ),
      write: store.write,
      compensate: store.compensate,
      recordSuccess: (identity) {
        failOwnerCheck = true;
        return store.recordSuccess(identity);
      },
      reconcileSuccess: store.reconcileSuccess,
    );

    final completion = await runtime.handle(
      owner: ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 7,
      ),
      toolCall: ToolCallInfo(
        id: 'save-owner-failure',
        name: canonicalSaveSkillToolName,
        arguments: const {
          'name': 'Release Check',
          'content': '# Verify the release',
        },
      ),
    );

    expect(completion.disposition, SaveSkillRuntimeDisposition.effectUncertain);
    expect(repository.getAll(), isEmpty);
    expect(notifier.pendingMutationReceiptCount, 0);
  });
}

final class _DelayedSkillRepository extends SkillRepository {
  _DelayedSkillRepository() : super.inMemory();

  Completer<void> saveStarted = Completer<void>();
  Completer<void>? _release;

  void delayNextSave() {
    saveStarted = Completer<void>();
    _release = Completer<void>();
  }

  void releaseSave() => _release?.complete();

  @override
  Future<void> save(Skill skill) async {
    final release = _release;
    if (release != null) {
      saveStarted.complete();
      await release.future;
      if (identical(_release, release)) {
        _release = null;
      }
    }
    await super.save(skill);
  }
}
