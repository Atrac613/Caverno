import 'dart:io';

import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/application/caverno_cli_doctor.dart';
import 'package:caverno/features/terminal/application/caverno_cli_runtime_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const readyConfiguration = CavernoCliRuntimeConfiguration(
    baseUrl: 'http://localhost:1234/v1',
    model: 'qwen',
    apiKey: 'doctor-secret',
  );

  group('CavernoCliDoctor', () {
    test('reports healthy required checks with safety warnings', () async {
      Directory? inspectedRoot;
      final report =
          await CavernoCliDoctor(
            endpointProbe: (_) async =>
                const CavernoCliDoctorEndpointResult.success(<String>{'qwen'}),
            storageProbe: (root) async => inspectedRoot = root,
            projectProbe: (path) async => '/canonical/project',
          ).run(
            configuration: readyConfiguration,
            dataRoot: Directory('/tmp/caverno-doctor'),
            projectPath: '/tmp/project',
            disabledToolNames: const <String>{'computer_click', 'save_skill'},
          );

      expect(inspectedRoot?.path, '/tmp/caverno-doctor');
      expect(report.status, CavernoCliDoctorOverallStatus.warning);
      expect(report.exitCode, CavernoCliExitCode.success);
      expect(report.checks.map((check) => check.id), <String>[
        'configuration',
        'endpoint',
        'model',
        'storage',
        'project',
        'tool_runtime',
      ]);
      expect(report.checks.last.details['disabledTools'], <String>[
        'computer_click',
        'save_skill',
      ]);
      expect(report.toJson().toString(), isNot(contains('doctor-secret')));
    });

    test('rejects endpoint credentials without probing the endpoint', () async {
      var endpointProbed = false;
      final report =
          await CavernoCliDoctor(
            endpointProbe: (_) async {
              endpointProbed = true;
              return const CavernoCliDoctorEndpointResult.success(<String>{
                'qwen',
              });
            },
            storageProbe: (_) async {},
          ).run(
            configuration: const CavernoCliRuntimeConfiguration(
              baseUrl: 'http://user:password@localhost:1234/v1?token=secret',
              model: 'qwen',
              apiKey: 'doctor-secret',
            ),
            dataRoot: Directory('/tmp/caverno-doctor'),
            disabledToolNames: const <String>{},
          );

      expect(endpointProbed, isFalse);
      expect(report.exitCode, CavernoCliExitCode.input);
      expect(report.configuration['endpoint'], 'http://localhost:1234/v1');
      expect(report.toJson().toString(), isNot(contains('password')));
      expect(report.toJson().toString(), isNot(contains('token')));
      expect(report.toJson().toString(), isNot(contains('secret')));
    });

    test('maps endpoint and missing-model failures to unavailable', () async {
      final endpointFailure =
          await CavernoCliDoctor(
            endpointProbe: (_) async =>
                const CavernoCliDoctorEndpointResult.failure(
                  message: 'The endpoint is unavailable.',
                  remediation: 'Start the endpoint.',
                ),
            storageProbe: (_) async {},
          ).run(
            configuration: readyConfiguration,
            dataRoot: Directory('/tmp/caverno-doctor'),
            disabledToolNames: const <String>{},
          );
      expect(endpointFailure.exitCode, CavernoCliExitCode.unavailable);
      expect(
        _check(endpointFailure, 'model').status,
        CavernoCliDoctorCheckStatus.skipped,
      );

      final missingModel =
          await CavernoCliDoctor(
            endpointProbe: (_) async =>
                const CavernoCliDoctorEndpointResult.success(<String>{'other'}),
            storageProbe: (_) async {},
          ).run(
            configuration: readyConfiguration,
            dataRoot: Directory('/tmp/caverno-doctor'),
            disabledToolNames: const <String>{},
          );
      expect(missingModel.exitCode, CavernoCliExitCode.unavailable);
      expect(
        _check(missingModel, 'model').status,
        CavernoCliDoctorCheckStatus.fail,
      );
    });

    test(
      'prioritizes storage failure over service and project failures',
      () async {
        final report =
            await CavernoCliDoctor(
              endpointProbe: (_) async =>
                  const CavernoCliDoctorEndpointResult.failure(
                    message: 'The endpoint is unavailable.',
                    remediation: 'Start the endpoint.',
                  ),
              storageProbe: (_) async =>
                  throw const FileSystemException('secret'),
              projectProbe: (_) async =>
                  throw const FileSystemException('secret'),
            ).run(
              configuration: readyConfiguration,
              dataRoot: Directory('/tmp/caverno-doctor'),
              projectPath: '/missing/project',
              disabledToolNames: const <String>{},
            );

        expect(report.exitCode, CavernoCliExitCode.persistence);
        expect(_check(report, 'storage').message, isNot(contains('secret')));
        expect(_check(report, 'project').message, isNot(contains('secret')));
      },
    );

    test('maps an inaccessible optional project to input failure', () async {
      final report =
          await CavernoCliDoctor(
            endpointProbe: (_) async =>
                const CavernoCliDoctorEndpointResult.success(<String>{'qwen'}),
            storageProbe: (_) async {},
            projectProbe: (_) async =>
                throw const FileSystemException('denied'),
          ).run(
            configuration: readyConfiguration,
            dataRoot: Directory('/tmp/caverno-doctor'),
            projectPath: '/missing/project',
            disabledToolNames: const <String>{},
          );

      expect(report.exitCode, CavernoCliExitCode.input);
      expect(
        _check(report, 'project').status,
        CavernoCliDoctorCheckStatus.fail,
      );
    });
  });

  group('CavernoCliDoctorHttpProbe', () {
    test('uses the models endpoint and configured authorization', () async {
      late Uri requestedUri;
      late Map<String, String> requestedHeaders;
      final probe = CavernoCliDoctorHttpProbe(
        client: MockClient((request) async {
          requestedUri = request.url;
          requestedHeaders = request.headers;
          return http.Response('{"data":[{"id":"qwen"},{"id":"other"}]}', 200);
        }),
      );
      addTearDown(probe.close);

      final result = await probe.call(readyConfiguration);

      expect(result.isReady, isTrue);
      expect(result.modelIds, <String>{'qwen', 'other'});
      expect(requestedUri.toString(), 'http://localhost:1234/v1/models');
      expect(requestedHeaders['Authorization'], 'Bearer doctor-secret');
    });

    test('does not expose response bodies or client exceptions', () async {
      final httpFailure = CavernoCliDoctorHttpProbe(
        client: MockClient(
          (_) async => http.Response('doctor-secret password', 401),
        ),
      );
      addTearDown(httpFailure.close);
      final httpResult = await httpFailure.call(readyConfiguration);
      expect(httpResult.message, contains('HTTP 401'));
      expect(httpResult.message, isNot(contains('doctor-secret')));

      final clientFailure = CavernoCliDoctorHttpProbe(
        client: MockClient(
          (_) async => throw http.ClientException('doctor-secret'),
        ),
      );
      addTearDown(clientFailure.close);
      final clientResult = await clientFailure.call(readyConfiguration);
      expect(clientResult.isReady, isFalse);
      expect(clientResult.message, isNot(contains('doctor-secret')));
    });

    test('bounds endpoint latency with a timeout', () async {
      final probe = CavernoCliDoctorHttpProbe(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('{"data":[]}', 200);
        }),
        timeout: const Duration(milliseconds: 1),
      );
      addTearDown(probe.close);

      final result = await probe.call(readyConfiguration);

      expect(result.isReady, isFalse);
      expect(result.message, contains('timeout'));
    });
  });

  test('storage probe removes its temporary file', () async {
    final root = await Directory.systemTemp.createTemp(
      'caverno_cli_doctor_test_',
    );
    addTearDown(() => root.delete(recursive: true));

    await probeCavernoCliDoctorStorage(root);

    expect(await root.list().toList(), isEmpty);
  });
}

CavernoCliDoctorCheck _check(CavernoCliDoctorReport report, String id) {
  return report.checks.singleWhere((check) => check.id == id);
}
