import 'llama_cpp_slot_discovery.dart';
import 'llama_cpp_slot_transport.dart';

/// Runs one candidate pinned to [idSlot] (null when the endpoint has no usable
/// slots). The caller wires this to [LlamaCppSlotTransport.createChatCompletion]
/// with the candidate's own prompt/sampling, so the executor stays decoupled
/// from request construction.
typedef SlotCandidateRunner = Future<SlotChatResult> Function(int? idSlot);

/// Per-candidate outcome, preserving input order. A candidate that threw is
/// captured as a failure rather than aborting the batch, so Best-of-N (LL7) can
/// keep the candidates that succeeded.
class SlotCandidateOutcome {
  const SlotCandidateOutcome.success(
    SlotChatResult this.result,
    this.assignedSlot,
  ) : error = null;

  const SlotCandidateOutcome.failure(Object this.error, this.assignedSlot)
    : result = null;

  final SlotChatResult? result;
  final Object? error;

  /// The slot this candidate ran on, or null when unpinned (sequential
  /// fallback on a non-slot endpoint).
  final int? assignedSlot;

  bool get isSuccess => result != null;
}

/// LL20 parallel slot execution substrate.
///
/// Given a list of candidate runners and a discovered [SlotInventory], runs
/// them concurrently — each pinned to its own server slot via a worker pool so
/// no two in-flight candidates ever share a slot — and degrades to sequential
/// single-slot execution when the endpoint has no usable parallel slots. This
/// is the substrate LL7 (Best-of-N) and LL13 (parallel worktrees) build on.
class ParallelSlotExecutor {
  const ParallelSlotExecutor();

  /// Runs [candidates] and returns their outcomes in the same order.
  ///
  /// Concurrency is bounded by the number of assignable slots (idle slots are
  /// preferred) and, when given, [maxConcurrency]. With fewer than two
  /// assignable workers the candidates run sequentially, pinned to the single
  /// slot when one exists and unpinned otherwise.
  Future<List<SlotCandidateOutcome>> run({
    required List<SlotCandidateRunner> candidates,
    required SlotInventory inventory,
    int? maxConcurrency,
  }) async {
    if (candidates.isEmpty) return const [];

    final workerSlotIds = _workerSlotIds(
      inventory: inventory,
      candidateCount: candidates.length,
      maxConcurrency: maxConcurrency,
    );

    if (workerSlotIds.length < 2) {
      return _runSequential(
        candidates,
        workerSlotIds.isEmpty ? null : workerSlotIds.first,
      );
    }
    return _runParallel(candidates, workerSlotIds);
  }

  List<int> _workerSlotIds({
    required SlotInventory inventory,
    required int candidateCount,
    required int? maxConcurrency,
  }) {
    if (!inventory.supported) return const [];
    final idle = inventory.idleSlotIds;
    final assignable = idle.isNotEmpty ? idle : inventory.slotIds;
    if (assignable.isEmpty) return const [];

    var limit = assignable.length < candidateCount
        ? assignable.length
        : candidateCount;
    if (maxConcurrency != null && maxConcurrency < limit) {
      limit = maxConcurrency < 0 ? 0 : maxConcurrency;
    }
    return assignable.take(limit).toList(growable: false);
  }

  Future<List<SlotCandidateOutcome>> _runSequential(
    List<SlotCandidateRunner> candidates,
    int? slotId,
  ) async {
    final outcomes = <SlotCandidateOutcome>[];
    for (final candidate in candidates) {
      outcomes.add(await _runOne(candidate, slotId));
    }
    return outcomes;
  }

  Future<List<SlotCandidateOutcome>> _runParallel(
    List<SlotCandidateRunner> candidates,
    List<int> workerSlotIds,
  ) async {
    final outcomes = List<SlotCandidateOutcome?>.filled(
      candidates.length,
      null,
    );
    // Shared cursor: reads/increments are synchronous (no await between them),
    // so Dart's single-threaded loop makes this race-free across workers.
    var nextIndex = 0;

    Future<void> worker(int slotId) async {
      while (true) {
        if (nextIndex >= candidates.length) return;
        final index = nextIndex++;
        outcomes[index] = await _runOne(candidates[index], slotId);
      }
    }

    await Future.wait([for (final slotId in workerSlotIds) worker(slotId)]);
    return outcomes.cast<SlotCandidateOutcome>();
  }

  Future<SlotCandidateOutcome> _runOne(
    SlotCandidateRunner candidate,
    int? slotId,
  ) async {
    try {
      final result = await candidate(slotId);
      return SlotCandidateOutcome.success(result, slotId);
    } catch (error) {
      return SlotCandidateOutcome.failure(error, slotId);
    }
  }
}
