const int localHostBytesPerGiB = 1024 * 1024 * 1024;

class LocalHostResourceProfile {
  const LocalHostResourceProfile({
    required this.totalMemoryBytes,
    required this.appleSiliconUnifiedMemory,
    required this.detectionMethod,
    this.message,
  });

  const LocalHostResourceProfile.detected({
    required int totalMemoryBytes,
    required bool appleSiliconUnifiedMemory,
    required String detectionMethod,
    String? message,
  }) : this(
         totalMemoryBytes: totalMemoryBytes,
         appleSiliconUnifiedMemory: appleSiliconUnifiedMemory,
         detectionMethod: detectionMethod,
         message: message,
       );

  const LocalHostResourceProfile.unknown({String? message})
    : this(
        totalMemoryBytes: null,
        appleSiliconUnifiedMemory: false,
        detectionMethod: 'unknown',
        message: message,
      );

  final int? totalMemoryBytes;
  final bool appleSiliconUnifiedMemory;
  final String detectionMethod;
  final String? message;

  bool get hasDetectedMemory =>
      totalMemoryBytes != null && totalMemoryBytes! > 0;

  double? get totalMemoryGiB =>
      hasDetectedMemory ? totalMemoryBytes! / localHostBytesPerGiB : null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalHostResourceProfile &&
            totalMemoryBytes == other.totalMemoryBytes &&
            appleSiliconUnifiedMemory == other.appleSiliconUnifiedMemory &&
            detectionMethod == other.detectionMethod &&
            message == other.message;
  }

  @override
  int get hashCode => Object.hash(
    totalMemoryBytes,
    appleSiliconUnifiedMemory,
    detectionMethod,
    message,
  );

  @override
  String toString() {
    return 'LocalHostResourceProfile(totalMemoryBytes: $totalMemoryBytes, '
        'appleSiliconUnifiedMemory: $appleSiliconUnifiedMemory, '
        'detectionMethod: $detectionMethod, message: $message)';
  }
}
