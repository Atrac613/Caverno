import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';

import 'live_llm_benchmark_mcp_config.dart';

Future<void> main(List<String> args) async {
  final options = _RelayOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart tool/live_mcp_loopback_relay.dart '
      '--config PATH --output-config PATH --ready-file PATH',
    );
    exitCode = 64;
    return;
  }

  late final List<McpServerConfig> servers;
  try {
    servers = loadLiveLlmBenchmarkMcpServers(options.configPath);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final relays = <_EndpointRelay>[];
  final effectiveServers = <McpServerConfig>[];
  try {
    for (final server in servers) {
      if (server.type != McpServerType.http) {
        effectiveServers.add(server);
        continue;
      }
      final origin = Uri.parse(server.normalizedUrl);
      if (origin.scheme != 'http') {
        throw const FormatException(
          'The MCP loopback relay supports HTTP endpoints only.',
        );
      }
      final relay = await _EndpointRelay.start(origin);
      relays.add(relay);
      effectiveServers.add(server.copyWith(url: relay.effectiveUrl));
    }
  } on Object catch (error) {
    for (final relay in relays) {
      await relay.close();
    }
    stderr.writeln('Unable to start the MCP loopback relay: $error');
    exitCode = error is FormatException ? 64 : 70;
    return;
  }

  final outputFile = File(options.outputConfigPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    jsonEncode(effectiveServers.map((server) => server.toJson()).toList()),
    flush: true,
  );
  final readyFile = File(options.readyFile);
  readyFile.parent.createSync(recursive: true);
  readyFile.writeAsStringSync('${relays.length}\n', flush: true);
  stdout.writeln(
    'Live MCP loopback relay ready for ${relays.length} HTTP endpoint(s).',
  );

  final shutdown = Completer<void>();
  var shuttingDown = false;
  Future<void> stop() async {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    for (final relay in relays) {
      await relay.close();
    }
    shutdown.complete();
  }

  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => unawaited(stop())),
    ProcessSignal.sigterm.watch().listen((_) => unawaited(stop())),
  ];
  await shutdown.future;
  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
}

final class _EndpointRelay {
  _EndpointRelay._(this.origin, this.server);

  final Uri origin;
  final ServerSocket server;
  final Set<Socket> _activeSockets = <Socket>{};

  String get effectiveUrl => origin
      .replace(host: InternetAddress.loopbackIPv4.address, port: server.port)
      .toString();

  static Future<_EndpointRelay> start(Uri origin) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _EndpointRelay._(origin, server);
    server.listen(relay._accept);
    return relay;
  }

  Future<void> _accept(Socket client) async {
    Socket? upstream;
    _activeSockets.add(client);

    void closePair() {
      _activeSockets.remove(client);
      client.destroy();
      if (upstream != null) {
        _activeSockets.remove(upstream);
        upstream.destroy();
      }
    }

    try {
      final connectedUpstream = await Socket.connect(origin.host, origin.port);
      upstream = connectedUpstream;
      _activeSockets.add(connectedUpstream);
      client.listen(
        connectedUpstream.add,
        onError: (_) => closePair(),
        onDone: () => connectedUpstream.close(),
        cancelOnError: true,
      );
      connectedUpstream.listen(
        client.add,
        onError: (_) => closePair(),
        onDone: () => client.close(),
        cancelOnError: true,
      );
    } on Object catch (error) {
      stderr.writeln('MCP loopback relay connection failed: $error');
      closePair();
    }
  }

  Future<void> close() async {
    await server.close();
    for (final socket in _activeSockets.toList(growable: false)) {
      socket.destroy();
    }
    _activeSockets.clear();
  }
}

final class _RelayOptions {
  const _RelayOptions({
    required this.configPath,
    required this.outputConfigPath,
    required this.readyFile,
  });

  final String configPath;
  final String outputConfigPath;
  final String readyFile;

  static _RelayOptions? parse(List<String> args) {
    String? configPath;
    String? outputConfigPath;
    String? readyFile;
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      if (index + 1 >= args.length) {
        return null;
      }
      switch (argument) {
        case '--config':
          configPath = args[++index];
        case '--output-config':
          outputConfigPath = args[++index];
        case '--ready-file':
          readyFile = args[++index];
        default:
          return null;
      }
    }
    if (configPath == null ||
        configPath.isEmpty ||
        outputConfigPath == null ||
        outputConfigPath.isEmpty ||
        readyFile == null ||
        readyFile.isEmpty) {
      return null;
    }
    return _RelayOptions(
      configPath: configPath,
      outputConfigPath: outputConfigPath,
      readyFile: readyFile,
    );
  }
}
