import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/datasources/save_skill_runtime_contract.dart';
import '../../data/repositories/skill_repository.dart';
import '../../domain/entities/skill.dart';
import '../../domain/services/save_skill_tool_contract.dart';
import '../../domain/services/skill_markdown_parser.dart';

class SkillsState {
  const SkillsState({required this.skills});

  final List<Skill> skills;

  factory SkillsState.initial() => const SkillsState(skills: []);

  List<Skill> get enabledSkills =>
      skills.where((skill) => skill.isUsable).toList(growable: false);
}

enum SkillMutationCompensationDisposition {
  compensated,
  alreadyAbsent,
  conflict,
  unknownToken,
}

enum SkillMutationSettlementDisposition {
  settled,
  ownerExpired,
  conflict,
  unknownToken,
  effectUncertain,
}

/// Exact before-and-after receipt allocated before one skill mutation.
final class SkillMutationReceipt {
  const SkillMutationReceipt({
    required this.identity,
    required this.token,
    required this.before,
    required this.after,
  });

  final SaveSkillMutationIdentity identity;
  final String token;
  final Skill? before;
  final Skill after;
}

enum SkillMutationWriteDisposition {
  committed,
  rejectedBeforeEffect,
  ownerExpiredBeforeEffect,
  effectUncertainAfterEffect,
}

/// Result of a runtime mutation whose receipt exists before persistence starts.
final class SkillMutationWriteAttempt {
  const SkillMutationWriteAttempt.committed(this.receipt)
    : disposition = SkillMutationWriteDisposition.committed,
      error = null;

  const SkillMutationWriteAttempt.rejectedBeforeEffect(this.error)
    : disposition = SkillMutationWriteDisposition.rejectedBeforeEffect,
      receipt = null;

  const SkillMutationWriteAttempt.ownerExpiredBeforeEffect()
    : disposition = SkillMutationWriteDisposition.ownerExpiredBeforeEffect,
      receipt = null,
      error = null;

  const SkillMutationWriteAttempt.effectUncertainAfterEffect(
    this.receipt,
    this.error,
  ) : disposition = SkillMutationWriteDisposition.effectUncertainAfterEffect;

  final SkillMutationWriteDisposition disposition;
  final SkillMutationReceipt? receipt;
  final Object? error;
}

final skillsNotifierProvider = NotifierProvider<SkillsNotifier, SkillsState>(
  SkillsNotifier.new,
);

class SkillsNotifier extends Notifier<SkillsState> {
  static const maxPendingMutationReceipts = 64;
  static const maxSettledMutationReceipts = 128;

  late final SkillRepository _repository;
  final _uuid = const Uuid();
  final Map<String, SkillMutationReceipt> _pendingMutationReceipts = {};
  final Map<String, SaveSkillSuccessIdentity> _settledMutationReceipts = {};
  Future<void> _mutationTail = Future<void>.value();

  @override
  SkillsState build() {
    _repository = ref.read(skillRepositoryProvider);
    return SkillsState(skills: _repository.getAll());
  }

  List<Skill> get skillsSnapshot => List<Skill>.unmodifiable(state.skills);

  int get pendingMutationReceiptCount => _pendingMutationReceipts.length;
  int get settledMutationReceiptCount => _settledMutationReceipts.length;

  SkillMutationReceipt? pendingMutationReceipt(
    SaveSkillMutationIdentity identity,
    String token,
  ) {
    final receipt = _pendingMutationReceipts[token];
    return receipt?.identity == identity ? receipt : null;
  }

  Future<Skill> upsertMarkdown({
    String? existingId,
    required String markdown,
    bool enabled = true,
  }) async {
    return _serializeMutation(() async {
      final skill = _buildSkill(
        existingId: existingId,
        markdown: markdown,
        enabled: enabled,
      );
      await _repository.save(skill);
      _reload();
      final persisted = _repository.getById(skill.id);
      if (persisted != skill) {
        throw StateError('The persisted skill did not match the write.');
      }
      return persisted!;
    });
  }

  /// Persists one owner-bound mutation with a preallocated compensation token.
  Future<SkillMutationWriteAttempt> upsertMarkdownWithReceipt({
    required SaveSkillMutationIdentity identity,
    required bool Function() isOwnerCurrent,
    String? existingId,
    required String markdown,
  }) async {
    return _serializeMutation(() async {
      if (!isOwnerCurrent()) {
        return const SkillMutationWriteAttempt.ownerExpiredBeforeEffect();
      }
      if (_pendingMutationReceipts.length >= maxPendingMutationReceipts) {
        return SkillMutationWriteAttempt.rejectedBeforeEffect(
          StateError('Too many unsettled skill mutation receipts.'),
        );
      }
      final currentSkills = _repository.getAll();
      if (saveSkillCatalogDigest(currentSkills) !=
          identity.catalog.catalogDigest) {
        return SkillMutationWriteAttempt.rejectedBeforeEffect(
          StateError('The approved skill catalog changed before persistence.'),
        );
      }
      final expectedWriteDigest = saveSkillWriteDigest(
        SkillStoreWriteRequest(existingId: existingId, markdown: markdown),
      );
      if (identity.writeDigest != expectedWriteDigest) {
        return SkillMutationWriteAttempt.rejectedBeforeEffect(
          StateError('The skill write digest did not match its receipt.'),
        );
      }

      final Skill skill;
      try {
        skill = _buildSkill(
          existingId: existingId,
          markdown: markdown,
          enabled: true,
        );
      } catch (error) {
        return SkillMutationWriteAttempt.rejectedBeforeEffect(error);
      }
      final receipt = SkillMutationReceipt(
        identity: identity,
        token: _uuid.v4(),
        before: existingId == null ? null : _repository.getById(existingId),
        after: skill,
      );
      _pendingMutationReceipts[receipt.token] = receipt;

      try {
        await _repository.save(skill);
        _reload();
        final persisted = _repository.getById(skill.id);
        if (persisted != skill) {
          throw StateError(
            'The persisted skill did not match the write receipt.',
          );
        }
        return SkillMutationWriteAttempt.committed(receipt);
      } catch (error) {
        try {
          _reload();
        } catch (_) {
          // Preserve the preallocated receipt when state refresh also fails.
        }
        return SkillMutationWriteAttempt.effectUncertainAfterEffect(
          receipt,
          error,
        );
      }
    });
  }

  /// Reverts only when the stored skill still matches the receipt's write.
  Future<SkillMutationCompensationDisposition> compensateMutation(
    SaveSkillMutationIdentity identity,
    String token,
  ) async {
    return _serializeMutation(() async {
      final receipt = pendingMutationReceipt(identity, token);
      if (receipt == null) {
        return SkillMutationCompensationDisposition.unknownToken;
      }
      final current = _repository.getById(receipt.after.id);
      if (current == receipt.before) {
        _reload();
        _pendingMutationReceipts.remove(token);
        return receipt.before == null
            ? SkillMutationCompensationDisposition.alreadyAbsent
            : SkillMutationCompensationDisposition.compensated;
      }
      if (current != receipt.after) {
        return SkillMutationCompensationDisposition.conflict;
      }

      final before = receipt.before;
      try {
        if (before == null) {
          await _repository.delete(receipt.after.id);
        } else {
          await _repository.save(before);
        }
      } catch (_) {
        final recovered = _repository.getById(receipt.after.id);
        if (recovered != before) rethrow;
      }
      _reload();
      final reverted = _repository.getById(receipt.after.id);
      if (reverted != before) {
        throw StateError(
          'The compensated skill did not match its prior state.',
        );
      }
      _pendingMutationReceipts.remove(token);
      return SkillMutationCompensationDisposition.compensated;
    });
  }

  Future<SkillMutationSettlementDisposition> settleMutation({
    required SaveSkillMutationIdentity identity,
    required String token,
    required String savedSkillDigest,
    required bool Function() isOwnerCurrent,
  }) => _serializeMutation(() async {
    final successIdentity = SaveSkillSuccessIdentity(
      mutation: identity,
      compensationToken: token,
      savedSkillDigest: savedSkillDigest,
    );
    final receipt = pendingMutationReceipt(identity, token);
    if (receipt == null) {
      final settled = _settledMutationReceipts[token];
      if (settled != null) {
        return settled == successIdentity
            ? SkillMutationSettlementDisposition.settled
            : SkillMutationSettlementDisposition.conflict;
      }
      return _pendingMutationReceipts.containsKey(token)
          ? SkillMutationSettlementDisposition.conflict
          : SkillMutationSettlementDisposition.unknownToken;
    }
    final bool ownerCurrent;
    try {
      ownerCurrent = isOwnerCurrent();
    } catch (_) {
      return SkillMutationSettlementDisposition.effectUncertain;
    }
    if (!ownerCurrent) {
      return SkillMutationSettlementDisposition.ownerExpired;
    }
    if (saveSkillDigest(receipt.after) != savedSkillDigest ||
        _repository.getById(receipt.after.id) != receipt.after) {
      return SkillMutationSettlementDisposition.conflict;
    }
    if (_pendingMutationReceipts.remove(token) != receipt) {
      return SkillMutationSettlementDisposition.effectUncertain;
    }
    _rememberSettledMutation(successIdentity);
    return SkillMutationSettlementDisposition.settled;
  });

  Future<SkillMutationSettlementDisposition> reconcileMutationSettlement({
    required SaveSkillMutationIdentity identity,
    required String token,
    required String savedSkillDigest,
  }) => _serializeMutation(() async {
    final expected = SaveSkillSuccessIdentity(
      mutation: identity,
      compensationToken: token,
      savedSkillDigest: savedSkillDigest,
    );
    final settled = _settledMutationReceipts[token];
    if (settled != null) {
      return settled == expected
          ? SkillMutationSettlementDisposition.settled
          : SkillMutationSettlementDisposition.conflict;
    }
    return _pendingMutationReceipts.containsKey(token)
        ? SkillMutationSettlementDisposition.effectUncertain
        : SkillMutationSettlementDisposition.unknownToken;
  });

  Future<void> toggleSkill(String id, bool enabled) async {
    await _serializeMutation(() async {
      final skill = _repository.getById(id);
      if (skill == null || skill.enabled == enabled) {
        return;
      }
      await _repository.save(
        skill.copyWith(enabled: enabled, updatedAt: DateTime.now()),
      );
      _reload();
    });
  }

  Future<void> deleteSkill(String id) async {
    await _serializeMutation(() async {
      await _repository.delete(id);
      _reload();
    });
  }

  void _reload() {
    state = SkillsState(skills: _repository.getAll());
  }

  void _rememberSettledMutation(SaveSkillSuccessIdentity identity) {
    _settledMutationReceipts[identity.compensationToken] = identity;
    while (_settledMutationReceipts.length > maxSettledMutationReceipts) {
      _settledMutationReceipts.remove(_settledMutationReceipts.keys.first);
    }
  }

  Skill _buildSkill({
    required String? existingId,
    required String markdown,
    required bool enabled,
  }) {
    final parsed = SkillMarkdownParser.parse(markdown);
    final now = DateTime.now();
    final existing = existingId == null
        ? null
        : _repository.getById(existingId);
    return Skill(
      id: existing?.id ?? _uuid.v4(),
      name: parsed.name,
      description: parsed.description,
      whenToUse: parsed.whenToUse,
      content: parsed.content,
      enabled: existing?.enabled ?? enabled,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<T> _serializeMutation<T>(Future<T> Function() action) async {
    final predecessor = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    await predecessor;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }
}
