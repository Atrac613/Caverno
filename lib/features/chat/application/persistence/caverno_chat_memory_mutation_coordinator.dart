import 'dart:async';
import 'dart:io';

import '../../data/repositories/chat_memory_mutation_coordinator.dart';
import '../runtime/caverno_execution_lease.dart';

final class CavernoChatMemoryMutationTimeout implements Exception {
  const CavernoChatMemoryMutationTimeout(this.timeout);

  final Duration timeout;

  String get message =>
      'Timed out waiting for the global chat-memory mutation lease after '
      '${timeout.inMilliseconds} ms.';

  @override
  String toString() => 'CavernoChatMemoryMutationTimeout: $message';
}

/// Serializes short chat-memory refresh-and-merge operations per data root.
final class CavernoChatMemoryMutationCoordinator
    implements ChatMemoryMutationCoordinator {
  CavernoChatMemoryMutationCoordinator({
    required Directory dataRoot,
    required String frontend,
    this.retryInterval = const Duration(milliseconds: 20),
    this.timeout = const Duration(seconds: 5),
    CavernoExecutionLeaseService? leaseService,
  }) : _leaseService =
           leaseService ??
           CavernoExecutionLeaseService(dataRoot: dataRoot, frontend: frontend);

  final Duration retryInterval;
  final Duration timeout;
  final CavernoExecutionLeaseService _leaseService;

  @override
  Future<T> run<T>(Future<T> Function() mutation) async {
    final stopwatch = Stopwatch()..start();
    CavernoExecutionLeaseHandle? handle;
    while (handle == null) {
      try {
        handle = _leaseService.acquire(<CavernoExecutionLeaseResource>[
          CavernoExecutionLeaseResource.chatMemory(),
        ]);
      } on CavernoExecutionLeaseConflict {
        final remaining = timeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          throw CavernoChatMemoryMutationTimeout(timeout);
        }
        await Future<void>.delayed(
          remaining < retryInterval ? remaining : retryInterval,
        );
      }
    }

    try {
      return await mutation();
    } finally {
      handle.release();
    }
  }
}
