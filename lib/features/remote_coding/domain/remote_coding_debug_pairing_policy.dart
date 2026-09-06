/// Whether a pairing code may be entered by hand instead of scanned.
///
/// Scanning a QR is a proof of proximity: it says the person pairing can see
/// the desktop's screen. SA-26 measured what pairing confers — a paired device
/// can make the desktop run an arbitrary shell command, by sending a message
/// and approving the request it provokes — so that proof is load-bearing, and
/// manual entry removes it. Anyone who obtains the string can pair.
///
/// It exists because verification needs it. Nothing in SA-26 is reachable on a
/// simulator otherwise: `QrScannerPage` has no non-camera path and a simulator
/// cannot photograph the Mac's screen, so the session ends before its first
/// check.
///
/// Debug builds only, and profile is excluded as well as release: a profile
/// build is a shippable artifact.
///
/// The flags are constructor values rather than `kDebugMode` read inline, the
/// same shape [RemoteCodingListenPolicy] uses, so a test can assert the
/// disabled case instead of trusting the mode it happens to run in.
class RemoteCodingDebugPairingPolicy {
  const RemoteCodingDebugPairingPolicy({
    required this.isRelease,
    required this.isProfile,
  });

  /// Reads the same compile flags Flutter derives `kDebugMode` from.
  factory RemoteCodingDebugPairingPolicy.current() {
    return const RemoteCodingDebugPairingPolicy(
      isRelease: bool.fromEnvironment('dart.vm.product'),
      isProfile: bool.fromEnvironment('dart.vm.profile'),
    );
  }

  final bool isRelease;
  final bool isProfile;

  bool get allowsManualPairingEntry => !isRelease && !isProfile;
}
