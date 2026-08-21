import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('live LLM loopback relay', () {
    test(
      'preserves the base path and streams bytes before completion',
      () async {
        final temporaryDirectory = Directory.systemTemp.createTempSync(
          'live-llm-loopback-relay-test-',
        );
        final readyFile = File('${temporaryDirectory.path}/ready');
        final origin = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final releaseSecondEvent = Completer<void>();
        final requestSeen = Completer<String>();
        origin.listen((socket) {
          final request = StringBuffer();
          var responseStarted = false;
          socket.cast<List<int>>().transform(utf8.decoder).listen((
            chunk,
          ) async {
            request.write(chunk);
            if (responseStarted || !request.toString().contains('\r\n\r\n')) {
              return;
            }
            responseStarted = true;
            requestSeen.complete(request.toString().split('\r\n').first);
            socket.add(
              utf8.encode(
                'HTTP/1.1 200 OK\r\n'
                'Content-Type: text/event-stream\r\n'
                'Connection: close\r\n\r\n'
                'data: first\n\n',
              ),
            );
            await socket.flush();
            await releaseSecondEvent.future;
            socket.add(utf8.encode('data: second\n\n'));
            await socket.flush();
            await socket.close();
          });
        });

        final relay = await Process.start(_dartExecutable(), [
          '--disable-dart-dev',
          'tool/live_llm_loopback_relay.dart',
          '--base-url',
          'http://127.0.0.1:${origin.port}/v1/events?probe=streaming',
          '--ready-file',
          readyFile.path,
        ]);
        final relayStdout = relay.stdout.transform(utf8.decoder).join();
        final relayStderr = relay.stderr.transform(utf8.decoder).join();
        Socket? client;

        addTearDown(() async {
          if (!releaseSecondEvent.isCompleted) {
            releaseSecondEvent.complete();
          }
          client?.destroy();
          relay.kill(ProcessSignal.sigterm);
          await relay.exitCode.timeout(const Duration(seconds: 5));
          await origin.close();
          temporaryDirectory.deleteSync(recursive: true);
        });

        final effectiveBaseUrl = await _waitForReadyFile(readyFile);
        expect(effectiveBaseUrl, startsWith('http://127.0.0.1:'));
        expect(effectiveBaseUrl, endsWith('/v1/events?probe=streaming'));

        final effectiveUri = Uri.parse(effectiveBaseUrl);
        final connectedClient = await Socket.connect(
          effectiveUri.host,
          effectiveUri.port,
        );
        client = connectedClient;
        final firstEvent = Completer<void>();
        final responseDone = Completer<void>();
        final responseText = StringBuffer();
        connectedClient.cast<List<int>>().transform(utf8.decoder).listen((
          chunk,
        ) {
          responseText.write(chunk);
          if (!firstEvent.isCompleted &&
              responseText.toString().contains('data: first')) {
            firstEvent.complete();
          }
        }, onDone: responseDone.complete);
        connectedClient.write(
          'GET ${effectiveUri.path}?${effectiveUri.query} HTTP/1.1\r\n'
          'Host: ${effectiveUri.host}\r\n'
          'Connection: close\r\n\r\n',
        );
        await connectedClient.flush();

        await firstEvent.future.timeout(const Duration(seconds: 5));
        expect(responseText.toString(), isNot(contains('data: second')));
        expect(
          await requestSeen.future,
          'GET /v1/events?probe=streaming HTTP/1.1',
        );

        releaseSecondEvent.complete();
        await responseDone.future.timeout(const Duration(seconds: 5));
        expect(responseText.toString(), contains('data: second'));

        relay.kill(ProcessSignal.sigterm);
        expect(await relay.exitCode.timeout(const Duration(seconds: 5)), 0);
        expect(await relayStderr, isNot(contains('connection failed')));
        expect(await relayStdout, contains('Live LLM loopback relay ready'));
      },
    );

    test(
      'MCP relay rewrites HTTP servers and preserves stdio settings',
      () async {
        final temporaryDirectory = Directory.systemTemp.createTempSync(
          'live-mcp-loopback-relay-test-',
        );
        final origins = await Future.wait([
          HttpServer.bind(InternetAddress.loopbackIPv4, 0),
          HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        ]);
        for (var index = 0; index < origins.length; index += 1) {
          origins[index].listen((request) async {
            request.response.write('origin-$index:${request.uri.path}');
            await request.response.close();
          });
        }
        final sourceConfig = File('${temporaryDirectory.path}/source.json');
        final effectiveConfig = File(
          '${temporaryDirectory.path}/effective.json',
        );
        final readyFile = File('${temporaryDirectory.path}/ready');
        const secret = 'must-not-appear-in-process-output';
        sourceConfig.writeAsStringSync(
          jsonEncode([
            for (var index = 0; index < origins.length; index += 1)
              {
                'type': 'http',
                'url': 'http://127.0.0.1:${origins[index].port}/mcp/$index',
                'enabled': true,
                'trustState': 'trusted',
              },
            {
              'type': 'stdio',
              'command': '/usr/bin/example-mcp',
              'args': ['serve'],
              'env': {'EXAMPLE_TOKEN': secret},
              'enabled': true,
              'trustState': 'trusted',
            },
          ]),
        );
        final sourceContents = sourceConfig.readAsStringSync();
        final relay = await Process.start(_dartExecutable(), [
          '--disable-dart-dev',
          'tool/live_mcp_loopback_relay.dart',
          '--config',
          sourceConfig.path,
          '--output-config',
          effectiveConfig.path,
          '--ready-file',
          readyFile.path,
        ]);
        final relayStdout = relay.stdout.transform(utf8.decoder).join();
        final relayStderr = relay.stderr.transform(utf8.decoder).join();

        addTearDown(() async {
          relay.kill(ProcessSignal.sigterm);
          await relay.exitCode.timeout(const Duration(seconds: 5));
          for (final origin in origins) {
            await origin.close(force: true);
          }
          temporaryDirectory.deleteSync(recursive: true);
        });

        expect(await _waitForReadyFile(readyFile), '2');
        final decoded = jsonDecode(effectiveConfig.readAsStringSync()) as List;
        expect(decoded, hasLength(3));
        final effectiveUrls = decoded
            .take(2)
            .map((value) => Uri.parse((value as Map)['url'] as String))
            .toList(growable: false);
        expect(
          effectiveUrls.map((uri) => uri.host),
          everyElement(InternetAddress.loopbackIPv4.address),
        );
        expect(effectiveUrls.map((uri) => uri.port).toSet(), hasLength(2));
        expect(effectiveUrls[0].path, '/mcp/0');
        expect(effectiveUrls[1].path, '/mcp/1');
        expect((decoded.last as Map)['command'], '/usr/bin/example-mcp');
        expect(((decoded.last as Map)['env'] as Map)['EXAMPLE_TOKEN'], secret);
        expect(sourceConfig.readAsStringSync(), sourceContents);

        final client = HttpClient();
        addTearDown(client.close);
        for (var index = 0; index < effectiveUrls.length; index += 1) {
          final request = await client.getUrl(effectiveUrls[index]);
          final response = await request.close();
          expect(
            await response.transform(utf8.decoder).join(),
            'origin-$index:/mcp/$index',
          );
        }

        relay.kill(ProcessSignal.sigterm);
        expect(await relay.exitCode.timeout(const Duration(seconds: 5)), 0);
        expect(await relayStdout, isNot(contains(secret)));
        expect(await relayStderr, isNot(contains(secret)));
      },
    );

    test(
      'wrapper manages MCP relay config lifecycle without printing secrets',
      () async {
        final temporaryDirectory = Directory.systemTemp.createTempSync(
          'live-mcp-loopback-wrapper-test-',
        );
        final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        const secret = 'wrapper-secret-value';
        final sourceConfig = File('${temporaryDirectory.path}/source.json')
          ..writeAsStringSync(
            jsonEncode([
              {
                'type': 'http',
                'url': 'http://127.0.0.1:${origin.port}/mcp',
                'enabled': true,
                'trustState': 'trusted',
              },
              {
                'type': 'stdio',
                'command': '/usr/bin/example-mcp',
                'env': {'TOKEN': secret},
                'enabled': true,
                'trustState': 'trusted',
              },
            ]),
          );
        addTearDown(() async {
          await origin.close(force: true);
          temporaryDirectory.deleteSync(recursive: true);
        });

        final result = await Process.run(
          'bash',
          [
            'tool/with_live_llm_loopback.sh',
            '--',
            'bash',
            '-c',
            'test -s "\$CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH" && '
                'grep -q "http://127.0.0.1:" "\$CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH" && '
                'printf "%s\\n%s\\n%s\\n" '
                '"\$CAVERNO_BENCHMARK_CANARY_MCP_ORIGIN_CONFIG_PATH" '
                '"\$CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH" '
                '"\$CAVERNO_BENCHMARK_CANARY_MCP_RELAY_MODE"',
          ],
          environment: {
            ...Platform.environment,
            'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:${origin.port}/v1',
            'CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH': sourceConfig.path,
            'CAVERNO_DART_EXECUTABLE': _dartExecutable(),
          },
        );

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains(sourceConfig.path));
        expect(result.stdout, contains('MCP relay mode: loopbackTcp (1'));
        expect(result.stdout, isNot(contains(secret)));
        expect(result.stderr, isNot(contains(secret)));
        final effectivePath = RegExp(
          r'/[^\n]+/mcp-config\.json',
        ).allMatches(result.stdout as String).last.group(0)!;
        expect(File(effectivePath).existsSync(), isFalse);
      },
    );

    test(
      'wrapper exports relay evidence and preserves the child exit code',
      () async {
        final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => origin.close(force: true));
        final environment = {
          ...Platform.environment,
          'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:${origin.port}/v1',
          'CAVERNO_DART_EXECUTABLE': _dartExecutable(),
        };

        final environmentResult = await Process.run('bash', [
          'tool/with_live_llm_loopback.sh',
          '--',
          'bash',
          '-c',
          'printf "%s\\n%s\\n%s\\n" "\$CAVERNO_LLM_ORIGIN_BASE_URL" "\$CAVERNO_LLM_EFFECTIVE_BASE_URL" "\$CAVERNO_LLM_RELAY_MODE"',
        ], environment: environment);
        expect(
          environmentResult.exitCode,
          0,
          reason: '${environmentResult.stderr}',
        );
        expect(
          environmentResult.stdout,
          contains('http://127.0.0.1:${origin.port}/v1'),
        );
        expect(environmentResult.stdout, contains('loopbackTcp'));
        expect(
          RegExp(r'http://127\.0\.0\.1:\d+/v1')
              .allMatches(environmentResult.stdout as String)
              .map((match) => match.group(0))
              .whereType<String>(),
          isNotEmpty,
        );

        final failureResult = await Process.run('bash', [
          'tool/with_live_llm_loopback.sh',
          '--',
          '/usr/bin/false',
        ], environment: environment);
        expect(failureResult.exitCode, 1);
      },
    );

    test('concurrent wrappers allocate different loopback ports', () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      final environment = {
        ...Platform.environment,
        'CAVERNO_LLM_BASE_URL': 'http://127.0.0.1:${origin.port}/v1',
        'CAVERNO_DART_EXECUTABLE': _dartExecutable(),
      };

      Future<ProcessResult> runWrapper() => Process.run('bash', [
        'tool/with_live_llm_loopback.sh',
        '--',
        '/usr/bin/printenv',
        'CAVERNO_LLM_EFFECTIVE_BASE_URL',
      ], environment: environment);

      final results = await Future.wait([runWrapper(), runWrapper()]);
      expect(results.map((result) => result.exitCode), everyElement(0));
      final effectiveUrls = results
          .map(
            (result) => RegExp(
              r'http://127\.0\.0\.1:\d+/v1',
            ).allMatches(result.stdout as String).last.group(0),
          )
          .toSet();
      expect(effectiveUrls, hasLength(2));
    });

    test('rejects unsupported HTTPS origins before becoming ready', () async {
      final temporaryDirectory = Directory.systemTemp.createTempSync(
        'live-llm-loopback-relay-invalid-test-',
      );
      addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
      final result = await Process.run(_dartExecutable(), [
        '--disable-dart-dev',
        'tool/live_llm_loopback_relay.dart',
        '--base-url',
        'https://example.test/v1',
        '--ready-file',
        '${temporaryDirectory.path}/ready',
      ]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('requires an HTTP base URL'));
    });

    test('refuses to become ready when the origin is unreachable', () async {
      final temporaryDirectory = Directory.systemTemp.createTempSync(
        'live-llm-loopback-relay-unreachable-test-',
      );
      addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
      // Bind and release a port so nothing is listening on it: the relay can
      // still bind its own loopback socket, which is exactly the case that used
      // to be reported as ready.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      final readyFile = '${temporaryDirectory.path}/ready';

      final result = await Process.run(_dartExecutable(), [
        '--disable-dart-dev',
        'tool/live_llm_loopback_relay.dart',
        '--base-url',
        'http://127.0.0.1:$deadPort/v1',
        '--ready-file',
        readyFile,
      ]);

      expect(result.exitCode, 69);
      expect(result.stderr, contains('cannot reach 127.0.0.1:$deadPort'));
      expect(
        File(readyFile).existsSync(),
        isFalse,
        reason: 'a relay that cannot reach its origin must not claim readiness',
      );
    });

    test('wrapper hands over the relay log when the child fails', () {
      // Without this the child sees unexplained connection resets and the one
      // line saying why is deleted during cleanup.
      final script = File('tool/with_live_llm_loopback.sh').readAsStringSync();
      expect(script, contains('Live LLM loopback relay log:'));
      expect(
        script.indexOf('COMMAND_STATUS=\$?'),
        lessThan(script.indexOf('Live LLM loopback relay log:')),
      );
    });

    test('wrapper uses the repository-managed Dart runtime when available', () {
      final script = File('tool/with_live_llm_loopback.sh').readAsStringSync();
      expect(script, contains('[[ -f "\${ROOT_DIR}/.fvmrc" ]]'));
      expect(script, contains('CAVERNO_DART_EXECUTABLE'));
      expect(script, contains('DART_COMMAND=(fvm dart)'));
    });

    test('wrapper help points agents to the canonical runbook', () async {
      final result = await Process.run('bash', [
        'tool/with_live_llm_loopback.sh',
        '--help',
      ]);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('managed ephemeral IPv4 loopback relay'));
      expect(result.stdout, contains('docs/live_llm_canary_agent_runbook.md'));
    });

    test('agent entrypoints link to the canonical runbook', () {
      const runbookPath = 'docs/live_llm_canary_agent_runbook.md';
      final runbook = File(runbookPath).readAsStringSync();
      final agents = File('AGENTS.md').readAsStringSync();
      final claude = File('CLAUDE.md').readAsStringSync();
      final readme = File('README.md').readAsStringSync();

      expect(runbook, contains('## Smallest Useful Live Check'));
      expect(runbook, contains('CAVERNO_BENCHMARK_CANARY_MIN_POINTS=50'));
      expect(runbook, contains('## Evidence to Inspect'));
      expect(agents, contains(runbookPath));
      expect(claude, contains(runbookPath));
      expect(readme, contains(runbookPath));
    });
  });
}

String _dartExecutable() {
  final result = Process.runSync('which', ['dart']);
  if (result.exitCode != 0) {
    throw StateError('The Dart executable is required for relay tests.');
  }
  return (result.stdout as String).trim();
}

Future<String> _waitForReadyFile(File file) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (file.existsSync()) {
      final contents = file.readAsStringSync().trim();
      if (contents.isNotEmpty) {
        return contents;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('The relay did not write its ready file.');
}
