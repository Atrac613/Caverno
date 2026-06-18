enum LocalModelLifecycleState {
  loaded,
  loading,
  unloaded,
  sleeping,
  downloading,
  unknown,
}

class LocalManagedModel {
  const LocalManagedModel({
    required this.id,
    required this.state,
    required this.statusValue,
    this.path,
    this.ownedBy,
    this.contextWindowTokens,
    this.failed = false,
    this.exitCode,
    this.commandArguments = const [],
    this.metadataHints = const [],
  });

  final String id;
  final LocalModelLifecycleState state;
  final String statusValue;
  final String? path;
  final String? ownedBy;
  final int? contextWindowTokens;
  final bool failed;
  final int? exitCode;
  final List<String> commandArguments;
  final List<String> metadataHints;

  bool get isLoaded => state == LocalModelLifecycleState.loaded;

  bool get isInProgress =>
      state == LocalModelLifecycleState.loading ||
      state == LocalModelLifecycleState.downloading;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalManagedModel &&
            id == other.id &&
            state == other.state &&
            statusValue == other.statusValue &&
            path == other.path &&
            ownedBy == other.ownedBy &&
            contextWindowTokens == other.contextWindowTokens &&
            failed == other.failed &&
            exitCode == other.exitCode &&
            _listEquals(commandArguments, other.commandArguments) &&
            _listEquals(metadataHints, other.metadataHints);
  }

  @override
  int get hashCode => Object.hash(
    id,
    state,
    statusValue,
    path,
    ownedBy,
    contextWindowTokens,
    failed,
    exitCode,
    Object.hashAll(commandArguments),
    Object.hashAll(metadataHints),
  );

  @override
  String toString() {
    return 'LocalManagedModel(id: $id, state: $state, '
        'statusValue: $statusValue, path: $path, ownedBy: $ownedBy, '
        'contextWindowTokens: $contextWindowTokens, failed: $failed, '
        'exitCode: $exitCode, commandArguments: $commandArguments, '
        'metadataHints: $metadataHints)';
  }
}

class LocalModelLifecycleCatalog {
  const LocalModelLifecycleCatalog({
    required this.supported,
    required this.models,
    this.message,
  });

  const LocalModelLifecycleCatalog.supported({
    required List<LocalManagedModel> models,
    String? message,
  }) : this(supported: true, models: models, message: message);

  const LocalModelLifecycleCatalog.unsupported({String? message})
    : this(supported: false, models: const [], message: message);

  final bool supported;
  final List<LocalManagedModel> models;
  final String? message;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalModelLifecycleCatalog &&
            supported == other.supported &&
            _listEquals(models, other.models) &&
            message == other.message;
  }

  @override
  int get hashCode => Object.hash(supported, Object.hashAll(models), message);

  @override
  String toString() {
    return 'LocalModelLifecycleCatalog(supported: $supported, '
        'models: $models, message: $message)';
  }
}

class LocalModelLifecycleActionResult {
  const LocalModelLifecycleActionResult({
    required this.supported,
    required this.succeeded,
    required this.message,
    this.statusCode,
  });

  const LocalModelLifecycleActionResult.success({required String message})
    : this(supported: true, succeeded: true, message: message);

  const LocalModelLifecycleActionResult.unsupported({
    required String message,
    int? statusCode,
  }) : this(
         supported: false,
         succeeded: false,
         message: message,
         statusCode: statusCode,
       );

  const LocalModelLifecycleActionResult.failure({
    required String message,
    int? statusCode,
  }) : this(
         supported: true,
         succeeded: false,
         message: message,
         statusCode: statusCode,
       );

  final bool supported;
  final bool succeeded;
  final String message;
  final int? statusCode;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalModelLifecycleActionResult &&
            supported == other.supported &&
            succeeded == other.succeeded &&
            message == other.message &&
            statusCode == other.statusCode;
  }

  @override
  int get hashCode => Object.hash(supported, succeeded, message, statusCode);

  @override
  String toString() {
    return 'LocalModelLifecycleActionResult(supported: $supported, '
        'succeeded: $succeeded, message: $message, statusCode: $statusCode)';
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
