import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _RelayOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart tool/live_llm_loopback_relay.dart '
      '--base-url URL --ready-file PATH',
    );
    exitCode = 64;
    return;
  }

  final origin = Uri.tryParse(options.baseUrl);
  if (origin == null ||
      origin.scheme != 'http' ||
      origin.host.isEmpty ||
      origin.hasFragment ||
      origin.userInfo.isNotEmpty) {
    stderr.writeln(
      'The loopback relay requires an HTTP base URL without credentials or a fragment.',
    );
    exitCode = 64;
    return;
  }
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final activeSockets = <Socket>{};
  final shutdown = Completer<void>();
  var shuttingDown = false;

  Future<void> stop() async {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    await server.close();
    for (final socket in activeSockets.toList(growable: false)) {
      socket.destroy();
    }
    if (!shutdown.isCompleted) {
      shutdown.complete();
    }
  }

  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => unawaited(stop())),
    ProcessSignal.sigterm.watch().listen((_) => unawaited(stop())),
  ];

  server.listen((client) async {
    Socket? upstream;
    activeSockets.add(client);

    void closePair() {
      activeSockets.remove(client);
      client.destroy();
      if (upstream != null) {
        activeSockets.remove(upstream);
        upstream.destroy();
      }
    }

    try {
      final connectedUpstream = await Socket.connect(origin.host, origin.port);
      upstream = connectedUpstream;
      activeSockets.add(connectedUpstream);
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
      stderr.writeln('Loopback relay connection failed: $error');
      closePair();
    }
  });

  final effectiveBaseUrl = origin
      .replace(host: InternetAddress.loopbackIPv4.address, port: server.port)
      .toString();
  final readyFile = File(options.readyFile);
  readyFile.parent.createSync(recursive: true);
  readyFile.writeAsStringSync('$effectiveBaseUrl\n', flush: true);
  stdout.writeln(
    'Live LLM loopback relay ready: $effectiveBaseUrl -> ${options.baseUrl}',
  );

  await shutdown.future;
  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
}

final class _RelayOptions {
  const _RelayOptions({required this.baseUrl, required this.readyFile});

  final String baseUrl;
  final String readyFile;

  static _RelayOptions? parse(List<String> args) {
    String? baseUrl;
    String? readyFile;
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      if (index + 1 >= args.length) {
        return null;
      }
      switch (argument) {
        case '--base-url':
          baseUrl = args[++index];
        case '--ready-file':
          readyFile = args[++index];
        default:
          return null;
      }
    }
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        readyFile == null ||
        readyFile.isEmpty) {
      return null;
    }
    return _RelayOptions(baseUrl: baseUrl, readyFile: readyFile);
  }
}
