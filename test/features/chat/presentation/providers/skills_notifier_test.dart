import 'dart:async';

import 'package:caverno/features/chat/data/datasources/save_skill_runtime_contract.dart';
import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/save_skill_tool_contract.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SkillRepository repository;
  late ProviderContainer container;
  late SkillsNotifier notifier;

  setUp(() {
    repository = SkillRepository.inMemory();
    (container, notifier) = _notifierFor(repository);
    addTearDown(container.dispose);
  });

  test('settles an exact create receipt without changing the skill', () async {
    final markdown = _markdown('Release Check', 'First body');
    final identity = _identity(notifier, markdown: markdown);
    final attempt = await _write(notifier, identity, markdown: markdown);
    final receipt = attempt.receipt!;

    expect(attempt.disposition, SkillMutationWriteDisposition.committed);
    expect(receipt.before, isNull);
    expect(receipt.after.normalizedName, 'Release Check');
    expect(repository.getById(receipt.after.id), receipt.after);
    expect(
      await _settle(notifier, identity, receipt),
      SkillMutationSettlementDisposition.settled,
    );
    expect(
      await _settle(notifier, identity, receipt),
      SkillMutationSettlementDisposition.settled,
    );
    expect(notifier.settledMutationReceiptCount, 1);
    expect(repository.getById(receipt.after.id), receipt.after);
  });

  test('compensates an exact create and consumes its token', () async {
    final markdown = _markdown('Release Check', 'First body');
    final identity = _identity(notifier, markdown: markdown);
    final receipt = (await _write(
      notifier,
      identity,
      markdown: markdown,
    )).receipt!;

    final disposition = await notifier.compensateMutation(
      identity,
      receipt.token,
    );

    expect(disposition, SkillMutationCompensationDisposition.compensated);
    expect(repository.getById(receipt.after.id), isNull);
    expect(container.read(skillsNotifierProvider).skills, isEmpty);
    expect(
      await notifier.compensateMutation(identity, receipt.token),
      SkillMutationCompensationDisposition.unknownToken,
    );
  });

  test('compensates an update by restoring its exact prior value', () async {
    final created = await notifier.upsertMarkdown(
      markdown: _markdown('Release Check', 'First body'),
    );
    final markdown = _markdown('Release Check', 'Updated body');
    final identity = _identity(
      notifier,
      existingId: created.id,
      markdown: markdown,
    );
    final receipt = (await _write(
      notifier,
      identity,
      existingId: created.id,
      markdown: markdown,
    )).receipt!;

    final disposition = await notifier.compensateMutation(
      identity,
      receipt.token,
    );

    expect(disposition, SkillMutationCompensationDisposition.compensated);
    expect(repository.getById(created.id), created);
    expect(container.read(skillsNotifierProvider).skills.single, created);
  });

  test('refuses to overwrite a later skill mutation', () async {
    final markdown = _markdown('Release Check', 'First body');
    final identity = _identity(notifier, markdown: markdown);
    final receipt = (await _write(
      notifier,
      identity,
      markdown: markdown,
    )).receipt!;
    await notifier.upsertMarkdown(
      existingId: receipt.after.id,
      markdown: _markdown('Release Check', 'Later body'),
    );

    final disposition = await notifier.compensateMutation(
      identity,
      receipt.token,
    );

    expect(disposition, SkillMutationCompensationDisposition.conflict);
    expect(repository.getById(receipt.after.id)?.content, '# Later body');
  });

  test('rejects token poison across owner, call, and every digest', () async {
    final markdown = _markdown('Release Check', 'First body');
    final identity = _identity(notifier, markdown: markdown);
    final receipt = (await _write(
      notifier,
      identity,
      markdown: markdown,
    )).receipt!;

    for (final kind in ['owner', 'call', 'argument', 'catalog', 'write']) {
      final poisoned = _poisonIdentity(identity, kind);
      expect(notifier.pendingMutationReceipt(poisoned, receipt.token), isNull);
      expect(
        await _settle(notifier, poisoned, receipt),
        SkillMutationSettlementDisposition.conflict,
      );
      expect(
        await notifier.compensateMutation(poisoned, receipt.token),
        SkillMutationCompensationDisposition.unknownToken,
        reason: kind,
      );
      expect(repository.getById(receipt.after.id), receipt.after);
    }

    expect(
      await _settle(notifier, identity, receipt),
      SkillMutationSettlementDisposition.settled,
    );
    for (final kind in ['owner', 'call', 'argument', 'catalog', 'write']) {
      expect(
        await _settle(notifier, _poisonIdentity(identity, kind), receipt),
        SkillMutationSettlementDisposition.conflict,
        reason: 'settled $kind poison',
      );
    }
  });

  test(
    'bounds settled receipt tombstones while keeping recent identity',
    () async {
      SkillMutationReceipt? first;
      SaveSkillMutationIdentity? firstIdentity;
      SkillMutationReceipt? latest;
      SaveSkillMutationIdentity? latestIdentity;
      for (
        var index = 0;
        index <= SkillsNotifier.maxSettledMutationReceipts;
        index += 1
      ) {
        final markdown = _markdown('Settled $index', 'Body $index');
        final identity = _identity(
          notifier,
          toolCallId: 'settled-call-$index',
          markdown: markdown,
        );
        final receipt = (await _write(
          notifier,
          identity,
          markdown: markdown,
        )).receipt!;
        expect(
          await _settle(notifier, identity, receipt),
          SkillMutationSettlementDisposition.settled,
        );
        first ??= receipt;
        firstIdentity ??= identity;
        latest = receipt;
        latestIdentity = identity;
      }

      expect(
        notifier.settledMutationReceiptCount,
        SkillsNotifier.maxSettledMutationReceipts,
      );
      expect(
        await _reconcile(notifier, firstIdentity!, first!),
        SkillMutationSettlementDisposition.unknownToken,
      );
      expect(
        await _reconcile(notifier, latestIdentity!, latest!),
        SkillMutationSettlementDisposition.settled,
      );
    },
  );

  test(
    'retains all unsettled receipts and rejects capacity before effect',
    () async {
      for (
        var index = 0;
        index < SkillsNotifier.maxPendingMutationReceipts;
        index += 1
      ) {
        final markdown = _markdown('Skill $index', 'Body $index');
        final identity = _identity(
          notifier,
          toolCallId: 'call-$index',
          markdown: markdown,
        );
        final attempt = await _write(notifier, identity, markdown: markdown);
        expect(attempt.disposition, SkillMutationWriteDisposition.committed);
      }
      final overflowMarkdown = _markdown('Overflow', 'Must not persist');
      final overflow = await _write(
        notifier,
        _identity(
          notifier,
          toolCallId: 'call-overflow',
          markdown: overflowMarkdown,
        ),
        markdown: overflowMarkdown,
      );

      expect(
        overflow.disposition,
        SkillMutationWriteDisposition.rejectedBeforeEffect,
      );
      expect(notifier.pendingMutationReceiptCount, 64);
      expect(
        repository.getAll().where((skill) => skill.name == 'Overflow'),
        isEmpty,
      );
    },
  );

  test(
    'compensates a commit-then-throw write from its pre-effect receipt',
    () async {
      final throwingRepository = _CommitThenThrowSkillRepository();
      final (throwingContainer, throwingNotifier) = _notifierFor(
        throwingRepository,
      );
      addTearDown(throwingContainer.dispose);
      final markdown = _markdown('Release Check', 'First body');
      final identity = _identity(throwingNotifier, markdown: markdown);

      final attempt = await _write(
        throwingNotifier,
        identity,
        markdown: markdown,
      );

      expect(
        attempt.disposition,
        SkillMutationWriteDisposition.effectUncertainAfterEffect,
      );
      expect(throwingRepository.getById(attempt.receipt!.after.id), isNotNull);
      expect(
        await throwingNotifier.compensateMutation(
          identity,
          attempt.receipt!.token,
        ),
        SkillMutationCompensationDisposition.compensated,
      );
      expect(throwingRepository.getById(attempt.receipt!.after.id), isNull);
    },
  );

  test(
    'retains a readback mismatch until exact reconciliation is possible',
    () async {
      final mismatchingRepository = _ReadbackMismatchSkillRepository();
      final (mismatchingContainer, mismatchingNotifier) = _notifierFor(
        mismatchingRepository,
      );
      addTearDown(mismatchingContainer.dispose);
      final markdown = _markdown('Release Check', 'First body');
      final identity = _identity(mismatchingNotifier, markdown: markdown);

      final attempt = await _write(
        mismatchingNotifier,
        identity,
        markdown: markdown,
      );
      final receipt = attempt.receipt!;
      expect(
        attempt.disposition,
        SkillMutationWriteDisposition.effectUncertainAfterEffect,
      );
      expect(
        await mismatchingNotifier.compensateMutation(identity, receipt.token),
        SkillMutationCompensationDisposition.conflict,
      );
      expect(
        mismatchingNotifier.pendingMutationReceipt(identity, receipt.token),
        receipt,
      );

      mismatchingRepository.poisonReadback = false;
      expect(
        await mismatchingNotifier.compensateMutation(identity, receipt.token),
        SkillMutationCompensationDisposition.compensated,
      );
      expect(mismatchingRepository.getById(receipt.after.id), isNull);
    },
  );

  test(
    'delayed compensation never overwrites a queued successor write',
    () async {
      final delayedRepository = _DelayedSkillRepository();
      final (delayedContainer, delayedNotifier) = _notifierFor(
        delayedRepository,
      );
      addTearDown(delayedContainer.dispose);
      final existing = await delayedNotifier.upsertMarkdown(
        markdown: _markdown('Release Check', 'Base body'),
      );
      final runtimeMarkdown = _markdown('Release Check', 'Runtime body');
      final identity = _identity(
        delayedNotifier,
        existingId: existing.id,
        markdown: runtimeMarkdown,
      );
      delayedRepository.delayNextSave();

      final pendingRuntime = _write(
        delayedNotifier,
        identity,
        existingId: existing.id,
        markdown: runtimeMarkdown,
      );
      await delayedRepository.saveStarted.future;
      final successor = delayedNotifier.upsertMarkdown(
        existingId: existing.id,
        markdown: _markdown('Release Check', 'Successor body'),
      );
      delayedRepository.releaseSave();
      final attempt = await pendingRuntime;
      await successor;

      expect(
        await delayedNotifier.compensateMutation(
          identity,
          attempt.receipt!.token,
        ),
        SkillMutationCompensationDisposition.conflict,
      );
      expect(
        delayedRepository.getById(existing.id)?.content,
        '# Successor body',
      );
    },
  );

  test(
    'successor queued during compensation remains the final persisted value',
    () async {
      final delayedRepository = _DelayedSkillRepository();
      final (delayedContainer, delayedNotifier) = _notifierFor(
        delayedRepository,
      );
      addTearDown(delayedContainer.dispose);
      final existing = await delayedNotifier.upsertMarkdown(
        markdown: _markdown('Release Check', 'Base body'),
      );
      final runtimeMarkdown = _markdown('Release Check', 'Runtime body');
      final identity = _identity(
        delayedNotifier,
        existingId: existing.id,
        markdown: runtimeMarkdown,
      );
      final attempt = await _write(
        delayedNotifier,
        identity,
        existingId: existing.id,
        markdown: runtimeMarkdown,
      );
      delayedRepository.delayNextSave();

      final pendingCompensation = delayedNotifier.compensateMutation(
        identity,
        attempt.receipt!.token,
      );
      await delayedRepository.saveStarted.future;
      final successor = delayedNotifier.upsertMarkdown(
        existingId: existing.id,
        markdown: _markdown('Release Check', 'Successor body'),
      );
      delayedRepository.releaseSave();

      expect(
        await pendingCompensation,
        SkillMutationCompensationDisposition.compensated,
      );
      await successor;
      expect(
        delayedRepository.getById(existing.id)?.content,
        '# Successor body',
      );
    },
  );
}

(ProviderContainer, SkillsNotifier) _notifierFor(SkillRepository repository) {
  final container = ProviderContainer(
    overrides: [skillRepositoryProvider.overrideWithValue(repository)],
  );
  container.read(skillsNotifierProvider);
  return (container, container.read(skillsNotifierProvider.notifier));
}

Future<SkillMutationWriteAttempt> _write(
  SkillsNotifier notifier,
  SaveSkillMutationIdentity identity, {
  String? existingId,
  required String markdown,
}) => notifier.upsertMarkdownWithReceipt(
  identity: identity,
  isOwnerCurrent: () => true,
  existingId: existingId,
  markdown: markdown,
);

Future<SkillMutationSettlementDisposition> _settle(
  SkillsNotifier notifier,
  SaveSkillMutationIdentity identity,
  SkillMutationReceipt receipt,
) => notifier.settleMutation(
  identity: identity,
  token: receipt.token,
  savedSkillDigest: saveSkillDigest(receipt.after),
  isOwnerCurrent: () => true,
);

Future<SkillMutationSettlementDisposition> _reconcile(
  SkillsNotifier notifier,
  SaveSkillMutationIdentity identity,
  SkillMutationReceipt receipt,
) => notifier.reconcileMutationSettlement(
  identity: identity,
  token: receipt.token,
  savedSkillDigest: saveSkillDigest(receipt.after),
);

SaveSkillMutationIdentity _identity(
  SkillsNotifier notifier, {
  String toolCallId = 'save-call',
  String? existingId,
  required String markdown,
}) {
  final runtime = SaveSkillRuntimeIdentity(
    owner: _owner,
    toolCallId: toolCallId,
    toolName: canonicalSaveSkillToolName,
    argumentDigest: 'argument-$toolCallId',
  );
  return SaveSkillMutationIdentity(
    catalog: SaveSkillCatalogIdentity(
      runtime: runtime,
      catalogDigest: saveSkillCatalogDigest(notifier.skillsSnapshot),
    ),
    writeDigest: saveSkillWriteDigest(
      SkillStoreWriteRequest(existingId: existingId, markdown: markdown),
    ),
  );
}

SaveSkillMutationIdentity _poisonIdentity(
  SaveSkillMutationIdentity identity,
  String kind,
) {
  final runtime = identity.catalog.runtime;
  return SaveSkillMutationIdentity(
    catalog: SaveSkillCatalogIdentity(
      runtime: SaveSkillRuntimeIdentity(
        owner: kind == 'owner'
            ? ChatTurnOwner(
                conversationId: 'conversation-b',
                interactionGeneration: runtime.owner.interactionGeneration,
              )
            : runtime.owner,
        toolCallId: kind == 'call' ? 'other-call' : runtime.toolCallId,
        toolName: runtime.toolName,
        argumentDigest: kind == 'argument'
            ? 'other-argument'
            : runtime.argumentDigest,
      ),
      catalogDigest: kind == 'catalog'
          ? 'other-catalog'
          : identity.catalog.catalogDigest,
    ),
    writeDigest: kind == 'write' ? 'other-write' : identity.writeDigest,
  );
}

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);

String _markdown(String name, String body) =>
    '''
---
name: $name
---

# $body
''';

final class _CommitThenThrowSkillRepository extends SkillRepository {
  _CommitThenThrowSkillRepository() : super.inMemory();

  @override
  Future<void> save(Skill skill) async {
    await super.save(skill);
    throw StateError('repository write failed');
  }
}

final class _ReadbackMismatchSkillRepository extends SkillRepository {
  _ReadbackMismatchSkillRepository() : super.inMemory();

  bool poisonReadback = true;

  @override
  Skill? getById(String id) {
    final skill = super.getById(id);
    if (!poisonReadback || skill == null) return skill;
    return skill.copyWith(content: '${skill.content}\npoisoned');
  }
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
