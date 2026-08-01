import '../../domain/entities/mcp_tool_entity.dart';
import 'file_mutation_runtime_contract.dart';

/// Shared classification and lifecycle fence for one runtime adapter call.
final class FileMutationRuntimeState {
  FileMutationRuntimeState({
    required this.identity,
    required FileMutationLifecycleCallback acknowledgeLifecycle,
    required void Function() retireOwner,
  }) : _acknowledgeLifecycle = acknowledgeLifecycle,
       _retireOwner = retireOwner;

  final FileMutationRuntimeIdentity identity;
  final FileMutationLifecycleCallback _acknowledgeLifecycle;
  final void Function() _retireOwner;
  FileMutationRuntimeDisposition? _observedDisposition;
  bool effectStarted = false;

  FileMutationRuntimeAcknowledgement<Object?> readLifecycle() {
    final FileMutationRuntimeAcknowledgement<Object?> acknowledgement;
    try {
      acknowledgement = _acknowledgeLifecycle(identity);
    } catch (error) {
      markEffectUncertain();
      throw FileMutationRuntimeBoundaryException(
        'File mutation lifecycle acknowledgement failed: $error',
      );
    }
    if (acknowledgement.identity != identity) {
      observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw const FileMutationRuntimeBoundaryException(
        'File mutation lifecycle identity mismatch.',
      );
    }
    return acknowledgement;
  }

  FileMutationRuntimeAcknowledgement<Object?> acknowledgeLifecycle() {
    final acknowledgement = readLifecycle();
    requireCurrentLifecycle(acknowledgement);
    return acknowledgement;
  }

  void requireCurrentLifecycle(
    FileMutationRuntimeAcknowledgement<Object?> acknowledgement,
  ) {
    switch (acknowledgement.disposition) {
      case FileMutationRuntimeAcknowledgementDisposition.completed:
        return;
      case FileMutationRuntimeAcknowledgementDisposition.rejected:
        observe(FileMutationRuntimeDisposition.rejected);
      case FileMutationRuntimeAcknowledgementDisposition.ownerExpired:
        observe(FileMutationRuntimeDisposition.ownerExpired);
        _retireOwner();
      case FileMutationRuntimeAcknowledgementDisposition.effectUncertain:
        markEffectUncertain();
    }
    throw FileMutationRuntimeBoundaryException(
      acknowledgement.message ??
          'The file mutation lifecycle is no longer current.',
    );
  }

  T accept<T>(
    FileMutationRuntimeAcknowledgement<T> acknowledgement,
    String source,
  ) {
    if (acknowledgement.identity != identity) {
      observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw FileMutationRuntimeBoundaryException('$source identity mismatch.');
    }
    switch (acknowledgement.disposition) {
      case FileMutationRuntimeAcknowledgementDisposition.completed:
        final value = acknowledgement.value;
        if (value == null) {
          markEffectUncertain();
          throw FileMutationRuntimeBoundaryException(
            '$source returned no value.',
          );
        }
        return value;
      case FileMutationRuntimeAcknowledgementDisposition.rejected:
        observe(FileMutationRuntimeDisposition.rejected);
      case FileMutationRuntimeAcknowledgementDisposition.ownerExpired:
        observe(FileMutationRuntimeDisposition.ownerExpired);
        _retireOwner();
      case FileMutationRuntimeAcknowledgementDisposition.effectUncertain:
        markEffectUncertain();
    }
    throw FileMutationRuntimeBoundaryException(
      acknowledgement.message ?? '$source did not complete.',
    );
  }

  T? acceptNullable<T>(
    FileMutationRuntimeAcknowledgement<T> acknowledgement,
    String source,
  ) {
    if (acknowledgement.identity != identity) {
      observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw FileMutationRuntimeBoundaryException('$source identity mismatch.');
    }
    if (acknowledgement.disposition ==
        FileMutationRuntimeAcknowledgementDisposition.completed) {
      return acknowledgement.value;
    }
    switch (acknowledgement.disposition) {
      case FileMutationRuntimeAcknowledgementDisposition.completed:
        break;
      case FileMutationRuntimeAcknowledgementDisposition.rejected:
        observe(FileMutationRuntimeDisposition.rejected);
      case FileMutationRuntimeAcknowledgementDisposition.ownerExpired:
        observe(FileMutationRuntimeDisposition.ownerExpired);
        _retireOwner();
      case FileMutationRuntimeAcknowledgementDisposition.effectUncertain:
        markEffectUncertain();
    }
    throw FileMutationRuntimeBoundaryException(
      acknowledgement.message ?? '$source did not complete.',
    );
  }

  void ensureCurrent() {
    acknowledgeLifecycle();
  }

  void validateResult(McpToolResult result) {
    if (result.toolName != identity.toolName) {
      observe(FileMutationRuntimeDisposition.boundaryMismatch);
      throw const FileMutationRuntimeBoundaryException(
        'File mutation result tool identity mismatch.',
      );
    }
  }

  FileMutationRuntimeDisposition classify(McpToolResult? result) {
    final observed = _observedDisposition;
    if (observed != null) return observed;
    return result?.isSuccess == true
        ? FileMutationRuntimeDisposition.completed
        : FileMutationRuntimeDisposition.rejected;
  }

  void markEffectUncertain() {
    observe(FileMutationRuntimeDisposition.effectUncertain);
  }

  void observe(FileMutationRuntimeDisposition disposition) {
    if (_priority(disposition) > _priority(_observedDisposition)) {
      _observedDisposition = disposition;
    }
  }
}

final class FileMutationRuntimeBoundaryException implements Exception {
  const FileMutationRuntimeBoundaryException(this.message);

  final String message;

  @override
  String toString() => message;
}

int _priority(FileMutationRuntimeDisposition? disposition) =>
    switch (disposition) {
      null || FileMutationRuntimeDisposition.completed => 0,
      FileMutationRuntimeDisposition.rejected => 1,
      FileMutationRuntimeDisposition.ownerExpired => 2,
      FileMutationRuntimeDisposition.effectUncertain => 3,
      FileMutationRuntimeDisposition.boundaryMismatch => 4,
    };
