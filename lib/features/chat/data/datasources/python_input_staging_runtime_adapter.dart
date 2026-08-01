import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../domain/services/python_script_tool_contract.dart';
import '../../domain/services/python_staging_lease_registry.dart';
import 'python_input_staging.dart';
import 'python_script_runtime_contract.dart';

/// Filesystem adapter for exact, marker-verified Python staging cleanup.
final class PythonInputStagingRuntimeAdapter {
  PythonInputStagingRuntimeAdapter({String Function()? nonceFactory})
    : _nonceFactory = nonceFactory ?? _secureNonce;

  static const markerFileName = '.caverno-python-staging-owner';

  final String Function() _nonceFactory;

  Future<
    PythonRuntimeAcknowledgement<
      PythonScriptRuntimeIdentity,
      PythonStagingAllocation
    >
  >
  stage(PythonRuntimeStagingRequest request) async {
    StagedPythonInputs? staged;
    try {
      final attachment = request.attachment;
      staged = await PythonInputStaging.stage(
        imageBase64: attachment?.imageBase64,
        imageMimeType: attachment?.imageMimeType,
        originalImagePath: attachment?.originalImagePath,
        originalImageMimeType: attachment?.originalImageMimeType,
      );
      final canonicalDirectory = await _canonicalStagingDirectory(
        staged.workingDirectory,
      );
      final nonce = _requiredNonce(_nonceFactory());
      final marker = File(_join(canonicalDirectory, markerFileName));
      await marker.writeAsString(nonce, flush: true);
      final inputs = await _canonicalInputs(canonicalDirectory, staged.inputs);
      return PythonRuntimeAcknowledgement(
        identity: request.identity,
        disposition: PythonRuntimeAcknowledgementDisposition.completed,
        value: PythonStagingAllocation(
          stagedInputs: PythonStagedInputs(
            workingDirectory: canonicalDirectory,
            inputs: inputs,
          ),
          directoryIdentity: PythonStagingDirectoryIdentity(
            canonicalPath: canonicalDirectory,
            markerNonce: nonce,
          ),
        ),
      );
    } catch (error) {
      if (staged != null) {
        await _bestEffortDeleteFreshDirectory(staged.workingDirectory);
      }
      return PythonRuntimeAcknowledgement(
        identity: request.identity,
        disposition: PythonRuntimeAcknowledgementDisposition.effectUncertain,
        message: 'Python input staging could not be verified: $error',
      );
    }
  }

  Future<
    PythonRuntimeAcknowledgement<
      PythonStagingCleanupIdentity,
      PythonStagingCleanupOutcome
    >
  >
  cleanup(PythonRuntimeCleanupRequest request) async {
    final identity = request.identity;
    try {
      final directory = Directory(identity.directoryIdentity.canonicalPath);
      if (!await directory.exists()) {
        return _cleanupAcknowledgement(
          identity,
          PythonStagingCleanupOutcome.alreadyAbsent,
        );
      }
      final canonicalDirectory = await directory.resolveSymbolicLinks();
      if (!_samePath(
            canonicalDirectory,
            identity.directoryIdentity.canonicalPath,
          ) ||
          !await _isSafeStagingDirectory(canonicalDirectory)) {
        return _cleanupAcknowledgement(
          identity,
          PythonStagingCleanupOutcome.identityMismatch,
        );
      }
      final marker = File(_join(canonicalDirectory, markerFileName));
      if (!await marker.exists() ||
          await marker.readAsString() !=
              identity.directoryIdentity.markerNonce) {
        return _cleanupAcknowledgement(
          identity,
          PythonStagingCleanupOutcome.identityMismatch,
        );
      }
      await directory.delete(recursive: true);
      return _cleanupAcknowledgement(
        identity,
        await directory.exists()
            ? PythonStagingCleanupOutcome.failed
            : PythonStagingCleanupOutcome.deleted,
      );
    } catch (error) {
      return PythonRuntimeAcknowledgement(
        identity: identity,
        disposition: PythonRuntimeAcknowledgementDisposition.effectUncertain,
        value: PythonStagingCleanupOutcome.failed,
        message: 'Python staging cleanup could not be verified: $error',
      );
    }
  }

  Future<String> _canonicalStagingDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw StateError('The Python staging directory does not exist.');
    }
    final canonical = await directory.resolveSymbolicLinks();
    if (!await _isSafeStagingDirectory(canonical)) {
      throw StateError(
        'The Python staging directory is outside the temp root.',
      );
    }
    return canonical;
  }

  Future<List<Map<String, dynamic>>> _canonicalInputs(
    String canonicalDirectory,
    List<Map<String, dynamic>> inputs,
  ) async {
    final canonical = <Map<String, dynamic>>[];
    final prefix = '$canonicalDirectory${Platform.pathSeparator}';
    for (final input in inputs) {
      final rawPath = input['path'];
      if (rawPath is! String || rawPath.trim().isEmpty) {
        throw StateError('A staged Python input has no path.');
      }
      final path = await File(rawPath).resolveSymbolicLinks();
      if (!_startsWithPath(path, prefix)) {
        throw StateError(
          'A staged Python input escaped its working directory.',
        );
      }
      canonical.add({
        'name': input['name'],
        'path': path,
        'mime': input['mime'],
      });
    }
    return canonical;
  }

  Future<bool> _isSafeStagingDirectory(String path) async {
    final directory = Directory(path);
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final parent = await directory.parent.resolveSymbolicLinks();
    final name = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .lastOrNull;
    return _samePath(parent, tempRoot) &&
        name != null &&
        name.startsWith('caverno_python_');
  }

  Future<void> _bestEffortDeleteFreshDirectory(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) return;
      final canonical = await directory.resolveSymbolicLinks();
      if (await _isSafeStagingDirectory(canonical)) {
        await Directory(canonical).delete(recursive: true);
      }
    } catch (_) {
      // The effect-uncertain acknowledgement preserves cleanup ambiguity.
    }
  }

  PythonRuntimeAcknowledgement<
    PythonStagingCleanupIdentity,
    PythonStagingCleanupOutcome
  >
  _cleanupAcknowledgement(
    PythonStagingCleanupIdentity identity,
    PythonStagingCleanupOutcome outcome,
  ) {
    return PythonRuntimeAcknowledgement(
      identity: identity,
      disposition: PythonRuntimeAcknowledgementDisposition.completed,
      value: outcome,
    );
  }

  static String _secureNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _requiredNonce(String value) {
    if (value.isEmpty || value != value.trim()) {
      throw ArgumentError.value(value, 'markerNonce');
    }
    return value;
  }

  static String _join(String parent, String child) {
    return parent.endsWith(Platform.pathSeparator)
        ? '$parent$child'
        : '$parent${Platform.pathSeparator}$child';
  }

  static bool _startsWithPath(String path, String prefix) {
    return Platform.isWindows
        ? path.toLowerCase().startsWith(prefix.toLowerCase())
        : path.startsWith(prefix);
  }

  static bool _samePath(String first, String second) {
    return Platform.isWindows
        ? first.toLowerCase() == second.toLowerCase()
        : first == second;
  }
}
