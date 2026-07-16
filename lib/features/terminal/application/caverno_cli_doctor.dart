import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../settings/data/model_remote_datasource.dart';
import 'caverno_cli_contract.dart';
import 'caverno_cli_runtime_configuration.dart';

enum CavernoCliDoctorCheckStatus { pass, warning, fail, skipped }

enum CavernoCliDoctorOverallStatus { ready, warning, failed }

final class CavernoCliDoctorCheck {
  const CavernoCliDoctorCheck({
    required this.id,
    required this.status,
    required this.message,
    required this.durationMs,
    this.remediation,
    this.details = const <String, Object?>{},
  });

  final String id;
  final CavernoCliDoctorCheckStatus status;
  final String message;
  final int durationMs;
  final String? remediation;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'status': status.name,
    'message': message,
    'durationMs': durationMs,
    if (remediation != null) 'remediation': remediation,
    if (details.isNotEmpty) 'details': details,
  };
}

final class CavernoCliDoctorReport {
  CavernoCliDoctorReport({
    required this.configuration,
    required List<CavernoCliDoctorCheck> checks,
  }) : checks = List<CavernoCliDoctorCheck>.unmodifiable(checks);

  static const schemaName = 'caverno_cli_doctor_report';
  static const schemaVersion = 1;

  final Map<String, Object?> configuration;
  final List<CavernoCliDoctorCheck> checks;

  CavernoCliDoctorOverallStatus get status {
    if (checks.any(
      (check) => check.status == CavernoCliDoctorCheckStatus.fail,
    )) {
      return CavernoCliDoctorOverallStatus.failed;
    }
    if (checks.any(
      (check) => check.status == CavernoCliDoctorCheckStatus.warning,
    )) {
      return CavernoCliDoctorOverallStatus.warning;
    }
    return CavernoCliDoctorOverallStatus.ready;
  }

  int get exitCode {
    bool failed(String id) => checks.any(
      (check) =>
          check.id == id && check.status == CavernoCliDoctorCheckStatus.fail,
    );

    if (failed('storage')) {
      return CavernoCliExitCode.persistence;
    }
    if (failed('endpoint') || failed('model') || failed('tool_runtime')) {
      return CavernoCliExitCode.unavailable;
    }
    if (failed('configuration') || failed('project')) {
      return CavernoCliExitCode.input;
    }
    return CavernoCliExitCode.success;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaName': schemaName,
    'schemaVersion': schemaVersion,
    'type': 'doctor_report',
    'status': status.name,
    'exitCode': exitCode,
    'configuration': configuration,
    'checks': checks.map((check) => check.toJson()).toList(growable: false),
  };
}

final class CavernoCliDoctorEndpointResult {
  const CavernoCliDoctorEndpointResult._({
    required this.modelIds,
    required this.message,
    required this.remediation,
  });

  const CavernoCliDoctorEndpointResult.success(Set<String> modelIds)
    : this._(
        modelIds: modelIds,
        message: 'The configured endpoint returned a valid model catalog.',
        remediation: null,
      );

  const CavernoCliDoctorEndpointResult.failure({
    required String message,
    required String remediation,
  }) : this._(
         modelIds: const <String>{},
         message: message,
         remediation: remediation,
       );

  final Set<String> modelIds;
  final String message;
  final String? remediation;

  bool get isReady => remediation == null;
}

typedef CavernoCliDoctorEndpointProbe =
    Future<CavernoCliDoctorEndpointResult> Function(
      CavernoCliRuntimeConfiguration configuration,
    );
typedef CavernoCliDoctorStorageProbe = Future<void> Function(Directory root);
typedef CavernoCliDoctorProjectProbe = Future<String> Function(String path);

final class CavernoCliDoctorHttpProbe {
  CavernoCliDoctorHttpProbe({
    http.Client? client,
    this.timeout = const Duration(seconds: 2),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Future<CavernoCliDoctorEndpointResult> call(
    CavernoCliRuntimeConfiguration configuration,
  ) async {
    try {
      final response = await _client
          .get(
            _modelsUri(configuration.baseUrl),
            headers: <String, String>{
              'Accept': 'application/json',
              if (configuration.apiKey.isNotEmpty)
                'Authorization': 'Bearer ${configuration.apiKey}',
            },
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CavernoCliDoctorEndpointResult.failure(
          message:
              'The configured endpoint returned HTTP ${response.statusCode}.',
          remediation:
              'Verify that the endpoint is running and accepts the configured credentials.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const CavernoCliDoctorEndpointResult.failure(
          message: 'The model catalog response was not a JSON object.',
          remediation:
              'Verify that the endpoint implements the OpenAI-compatible models API.',
        );
      }
      final catalog = ModelRemoteDataSource.parseModelCatalogResponse(decoded);
      if (catalog.isEmpty) {
        return const CavernoCliDoctorEndpointResult.failure(
          message: 'The configured endpoint returned no usable model IDs.',
          remediation: 'Load at least one model and retry the doctor command.',
        );
      }
      return CavernoCliDoctorEndpointResult.success(
        catalog.map((entry) => entry.id).toSet(),
      );
    } on TimeoutException {
      return const CavernoCliDoctorEndpointResult.failure(
        message: 'The configured endpoint did not respond before the timeout.',
        remediation: 'Verify endpoint reachability and retry.',
      );
    } on FormatException {
      return const CavernoCliDoctorEndpointResult.failure(
        message: 'The configured endpoint returned malformed JSON.',
        remediation:
            'Verify that the endpoint implements the OpenAI-compatible models API.',
      );
    } on http.ClientException {
      return const CavernoCliDoctorEndpointResult.failure(
        message: 'The configured endpoint could not be reached.',
        remediation:
            'Verify endpoint reachability and credentials, then retry.',
      );
    } on SocketException {
      return const CavernoCliDoctorEndpointResult.failure(
        message: 'The configured endpoint could not be reached.',
        remediation:
            'Verify endpoint reachability and credentials, then retry.',
      );
    } on Object {
      return const CavernoCliDoctorEndpointResult.failure(
        message: 'The configured endpoint probe failed safely.',
        remediation: 'Verify endpoint configuration and retry.',
      );
    }
  }

  void close() => _client.close();

  Uri _modelsUri(String baseUrl) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse(
      normalized.endsWith('/models') ? normalized : '$normalized/models',
    );
  }
}

final class CavernoCliDoctor {
  const CavernoCliDoctor({
    required this.endpointProbe,
    this.storageProbe = probeCavernoCliDoctorStorage,
    this.projectProbe = probeCavernoCliDoctorProject,
  });

  final CavernoCliDoctorEndpointProbe endpointProbe;
  final CavernoCliDoctorStorageProbe storageProbe;
  final CavernoCliDoctorProjectProbe projectProbe;

  Future<CavernoCliDoctorReport> run({
    required CavernoCliRuntimeConfiguration configuration,
    required Directory dataRoot,
    required Set<String> disabledToolNames,
    String? projectPath,
  }) async {
    final checks = <CavernoCliDoctorCheck>[];
    final endpoint = _validatedEndpoint(configuration.baseUrl);
    final normalizedProject = projectPath?.trim();
    final reportConfiguration = <String, Object?>{
      'endpoint': _sanitizedEndpoint(configuration.baseUrl),
      'model': configuration.model,
      'dataRoot': dataRoot.absolute.path,
      if (normalizedProject != null && normalizedProject.isNotEmpty)
        'project': Directory(normalizedProject).absolute.path,
    };

    if (endpoint == null || configuration.model.trim().isEmpty) {
      checks.add(
        const CavernoCliDoctorCheck(
          id: 'configuration',
          status: CavernoCliDoctorCheckStatus.fail,
          message: 'The effective endpoint or model configuration is invalid.',
          durationMs: 0,
          remediation:
              'Set a valid HTTP endpoint and a non-empty model identifier.',
        ),
      );
      checks.addAll(const <CavernoCliDoctorCheck>[
        CavernoCliDoctorCheck(
          id: 'endpoint',
          status: CavernoCliDoctorCheckStatus.skipped,
          message:
              'The endpoint probe was skipped because configuration failed.',
          durationMs: 0,
        ),
        CavernoCliDoctorCheck(
          id: 'model',
          status: CavernoCliDoctorCheckStatus.skipped,
          message: 'The model check was skipped because configuration failed.',
          durationMs: 0,
        ),
      ]);
    } else {
      checks.add(
        CavernoCliDoctorCheck(
          id: 'configuration',
          status: CavernoCliDoctorCheckStatus.pass,
          message: 'The effective endpoint and model configuration is valid.',
          durationMs: 0,
          details: <String, Object?>{
            'endpoint': _sanitizedEndpoint(configuration.baseUrl),
            'model': configuration.model,
          },
        ),
      );
      final stopwatch = Stopwatch()..start();
      final endpointResult = await endpointProbe(configuration);
      stopwatch.stop();
      checks.add(
        CavernoCliDoctorCheck(
          id: 'endpoint',
          status: endpointResult.isReady
              ? CavernoCliDoctorCheckStatus.pass
              : CavernoCliDoctorCheckStatus.fail,
          message: endpointResult.message,
          durationMs: stopwatch.elapsedMilliseconds,
          remediation: endpointResult.remediation,
        ),
      );
      if (!endpointResult.isReady) {
        checks.add(
          const CavernoCliDoctorCheck(
            id: 'model',
            status: CavernoCliDoctorCheckStatus.skipped,
            message: 'The model check was skipped because the endpoint failed.',
            durationMs: 0,
          ),
        );
      } else if (endpointResult.modelIds.contains(configuration.model)) {
        checks.add(
          CavernoCliDoctorCheck(
            id: 'model',
            status: CavernoCliDoctorCheckStatus.pass,
            message: 'The configured model is available at the endpoint.',
            durationMs: 0,
            details: <String, Object?>{'model': configuration.model},
          ),
        );
      } else {
        checks.add(
          CavernoCliDoctorCheck(
            id: 'model',
            status: CavernoCliDoctorCheckStatus.fail,
            message: 'The configured model is not available at the endpoint.',
            durationMs: 0,
            remediation:
                'Load the configured model or select one returned by the endpoint.',
            details: <String, Object?>{'model': configuration.model},
          ),
        );
      }
    }

    checks.add(await _storageCheck(dataRoot));
    checks.add(await _projectCheck(normalizedProject));

    final disabledTools = disabledToolNames.toList()..sort();
    checks.add(
      CavernoCliDoctorCheck(
        id: 'tool_runtime',
        status: disabledTools.isEmpty
            ? CavernoCliDoctorCheckStatus.pass
            : CavernoCliDoctorCheckStatus.warning,
        message: disabledTools.isEmpty
            ? 'The terminal tool policy is ready.'
            : 'The terminal tool policy is ready with safety exclusions.',
        durationMs: 0,
        remediation: disabledTools.isEmpty
            ? null
            : 'Use the Caverno application for capabilities excluded from the headless CLI.',
        details: <String, Object?>{'disabledTools': disabledTools},
      ),
    );

    return CavernoCliDoctorReport(
      configuration: reportConfiguration,
      checks: checks,
    );
  }

  Future<CavernoCliDoctorCheck> _storageCheck(Directory dataRoot) async {
    final stopwatch = Stopwatch()..start();
    try {
      await storageProbe(dataRoot);
      stopwatch.stop();
      return CavernoCliDoctorCheck(
        id: 'storage',
        status: CavernoCliDoctorCheckStatus.pass,
        message: 'The data root is readable and writable.',
        durationMs: stopwatch.elapsedMilliseconds,
        details: <String, Object?>{'dataRoot': dataRoot.absolute.path},
      );
    } on Object {
      stopwatch.stop();
      return CavernoCliDoctorCheck(
        id: 'storage',
        status: CavernoCliDoctorCheckStatus.fail,
        message: 'The data root could not be inspected safely.',
        durationMs: stopwatch.elapsedMilliseconds,
        remediation:
            'Verify data-root permissions and remove any stale doctor probe file.',
        details: <String, Object?>{'dataRoot': dataRoot.absolute.path},
      );
    }
  }

  Future<CavernoCliDoctorCheck> _projectCheck(String? projectPath) async {
    if (projectPath == null || projectPath.isEmpty) {
      return const CavernoCliDoctorCheck(
        id: 'project',
        status: CavernoCliDoctorCheckStatus.skipped,
        message: 'No project path was requested.',
        durationMs: 0,
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final canonicalPath = await projectProbe(projectPath);
      stopwatch.stop();
      return CavernoCliDoctorCheck(
        id: 'project',
        status: CavernoCliDoctorCheckStatus.pass,
        message: 'The project directory is accessible.',
        durationMs: stopwatch.elapsedMilliseconds,
        details: <String, Object?>{'project': canonicalPath},
      );
    } on Object {
      stopwatch.stop();
      return CavernoCliDoctorCheck(
        id: 'project',
        status: CavernoCliDoctorCheckStatus.fail,
        message: 'The requested project directory is not accessible.',
        durationMs: stopwatch.elapsedMilliseconds,
        remediation: 'Provide an existing readable project directory.',
      );
    }
  }

  Uri? _validatedEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  String _sanitizedEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) {
      return 'invalid';
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
}

Future<void> probeCavernoCliDoctorStorage(Directory root) async {
  final normalizedRoot = Directory.fromUri(root.absolute.uri.normalizePath());
  await normalizedRoot.create(recursive: true);
  final probe = File(
    '${normalizedRoot.path}/.caverno-doctor-$pid-${DateTime.now().microsecondsSinceEpoch}',
  );
  Object? failure;
  try {
    await probe.writeAsString('doctor', flush: true);
    await probe.readAsString();
  } on Object catch (error) {
    failure = error;
  } finally {
    try {
      if (await probe.exists()) {
        await probe.delete();
      }
    } on Object catch (error) {
      failure ??= error;
    }
  }
  if (failure != null || await probe.exists()) {
    throw FileSystemException('The storage probe failed.');
  }
}

Future<String> probeCavernoCliDoctorProject(String path) async {
  final directory = Directory.fromUri(
    Directory(path).absolute.uri.normalizePath(),
  );
  if (!await directory.exists()) {
    throw FileSystemException('The project directory does not exist.');
  }
  await directory.list(followLinks: false).take(1).drain<void>();
  return directory.path;
}
